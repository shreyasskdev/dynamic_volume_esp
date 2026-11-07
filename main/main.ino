#include "soc/soc.h"
#include "soc/rtc_cntl_reg.h"
#include "AudioTools.h"
#include "BluetoothA2DPSink.h"
#include "BluetoothSerial.h"
#include <driver/i2s.h>

AnalogAudioStream out;
BluetoothA2DPSink a2dp_sink(out);
BluetoothSerial SerialBT;

// --- Microphone Pins ---
#define MIC_SCK 32
#define MIC_WS  33
#define MIC_SD  34
#define MIC_LR  27  // Pin acting as GND for L/R
#define I2S_MIC_PORT I2S_NUM_1

// --- Dynamic Auto-Volume Settings ---
float one_sec_mean   = 500.0;   // True mean over the last 1 full second
float quiet_level    = 500.0;   // Auto-adapts to room's quiet floor
float loud_level     = 4000.0;  // Auto-adapts to room's loudest 1-sec mean
int   min_volume     = 35;      // Minimum volume (0-127)
int   max_volume     = 127;     // 127 = Full 100% Volume!
bool  auto_range     = true;    // Automatically adjust quiet & loud range

int   current_volume = min_volume;
bool  first_window   = true;

// --- 1-Second Accumulator Variables ---
double rms_sum              = 0;
int    rms_count            = 0;
unsigned long window_start  = 0;
const unsigned long WINDOW_MS = 1000; // Strictly 1000ms (1 full second)

void setupMic() {
  pinMode(MIC_LR, OUTPUT);
  digitalWrite(MIC_LR, LOW);

  i2s_config_t i2s_config = {
    .mode = (i2s_mode_t)(I2S_MODE_MASTER | I2S_MODE_RX),
    .sample_rate = 16000,
    .bits_per_sample = I2S_BITS_PER_SAMPLE_32BIT,
    .channel_format = I2S_CHANNEL_FMT_ONLY_LEFT,
    .communication_format = I2S_COMM_FORMAT_STAND_I2S,
    .intr_alloc_flags = ESP_INTR_FLAG_LEVEL1,
    .dma_buf_count = 4,
    .dma_buf_len = 256,
    .use_apll = false
  };

  i2s_pin_config_t pin_config = {
    .bck_io_num = MIC_SCK,
    .ws_io_num = MIC_WS,
    .data_out_num = I2S_PIN_NO_CHANGE,
    .data_in_num = MIC_SD
  };

  i2s_driver_install(I2S_MIC_PORT, &i2s_config, 0, NULL);
  i2s_set_pin(I2S_MIC_PORT, &pin_config);
}

void handleFlutterCommands() {
  if (SerialBT.available()) {
    String cmd = SerialBT.readStringUntil('\n');
    cmd.trim();
    if (cmd.startsWith("SET:")) {
      cmd.remove(0, 4);
      int a, minv, maxv;
      float q, l;
      if (sscanf(cmd.c_str(), "%d,%f,%f,%d,%d", &a, &q, &l, &minv, &maxv) == 5) {
        auto_range  = (a == 1);
        quiet_level = q;
        loud_level  = max(q + 1500.0f, l);
        min_volume  = constrain(minv, 0, 127);
        max_volume  = constrain(maxv, 0, 127);
      }
    }
  }
}

void setup() {
  WRITE_PERI_REG(RTC_CNTL_BROWN_OUT_REG, 0);
  Serial.begin(115200);

  a2dp_sink.start("ESP32 Speaker");
  a2dp_sink.set_volume(current_volume);

  SerialBT.begin("ESP32 Speaker");
  Serial.println("Bluetooth Speaker + 1-Second Mean Auto-Volume Ready!");

  setupMic();
  window_start = millis();
}

void loop() {
  handleFlutterCommands();

  int32_t samples[128];
  size_t bytes_read = 0;
  i2s_read(I2S_MIC_PORT, &samples, sizeof(samples), &bytes_read, pdMS_TO_TICKS(25));
  int num_samples = bytes_read / 4;

  // 1. Continuously read mic and accumulate into rms_sum during the 1-second window
  if (num_samples > 0) {
    double dc_mean = 0;
    for (int i = 0; i < num_samples; i++) {
      dc_mean += (samples[i] >> 14);
    }
    dc_mean /= num_samples;

    double sum_squares = 0;
    for (int i = 0; i < num_samples; i++) {
      double centered = (samples[i] >> 14) - dc_mean;
      sum_squares += centered * centered;
    }
    
    float chunk_rms = sqrt(sum_squares / num_samples);
    rms_sum += chunk_rms;
    rms_count++;
  }

  // 2. ONLY AFTER 1 FULL SECOND (1000ms): Take the mean and update volume!
  unsigned long now = millis();
  if (now - window_start >= WINDOW_MS && rms_count > 0) {
    
    // Calculate the true mean of the entire 1-second window
    one_sec_mean = (float)(rms_sum / rms_count);

    // Reset accumulator for the next 1-second window
    rms_sum      = 0;
    rms_count    = 0;
    window_start = now;

    if (first_window && one_sec_mean > 10) {
      quiet_level  = one_sec_mean;
      loud_level   = one_sec_mean + 3000.0;
      first_window = false;
    }

    // 3. Auto-Adjusting Range (evaluated once per second)
    if (auto_range) {
      if (one_sec_mean < quiet_level) {
        quiet_level = (0.70 * quiet_level) + (0.30 * one_sec_mean);
      } else if (current_volume <= min_volume + 10) {
        quiet_level = (0.95 * quiet_level) + (0.05 * one_sec_mean);
      }

      float min_allowed_loud = quiet_level + 2000.0;

      if (one_sec_mean > loud_level) {
        loud_level = one_sec_mean; // Lock onto loudest 1-second average
      } else {
        loud_level = (0.97 * loud_level) + (0.03 * min_allowed_loud);
      }

      if (loud_level < min_allowed_loud) {
        loud_level = min_allowed_loud;
      }
    }

    // 4. Calculate New Volume from the 1-Second Mean
    float speaker_compensation = (current_volume - min_volume) * 8.0;
    float effective_quiet = quiet_level + 350.0 + speaker_compensation;
    float effective_loud  = max(effective_quiet + 800.0f, loud_level * 0.90f);

    int new_volume;
    if (one_sec_mean <= effective_quiet) {
      new_volume = min_volume;
    } else {
      new_volume = map((long)one_sec_mean, (long)effective_quiet, (long)effective_loud, min_volume, max_volume);
      new_volume = constrain(new_volume, min_volume, max_volume);
    }

    // 5. Apply Volume Update (Strictly once per second!)
    current_volume = new_volume;
    a2dp_sink.set_volume(current_volume);

    // 6. Print & Send to Flutter App (Once per second)
    Serial.printf("[1s Mean] Noise:%.0f | Quiet:%.0f | Loud:%.0f | Vol:%d/127\n",
                  one_sec_mean, quiet_level, loud_level, current_volume);

    if (SerialBT.hasClient()) {
      SerialBT.printf("{\"noise\":%.0f,\"vol\":%d,\"quiet\":%.0f,\"loud\":%.0f,\"minv\":%d,\"maxv\":%d,\"auto\":%d}\n",
                      one_sec_mean, current_volume, quiet_level, loud_level, min_volume, max_volume, auto_range ? 1 : 0);
    }
  }
}