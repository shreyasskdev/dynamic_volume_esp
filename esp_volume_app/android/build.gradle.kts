// android/build.gradle.kts

allprojects {
    repositories {
        // Fast mirrors
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        maven { url = uri("https://maven.aliyun.com/repository/google") }

        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

// 1. REGISTER THE OVERRIDE FIRST. This queues the action before plugins are evaluated.
subprojects {
    afterEvaluate {
        if (project.extensions.findByName("android") != null) {
            val androidExtension = project.extensions.getByName("android")
            try {
                // Use reflection to get the current compileSdk version
                val getCompileSdk = androidExtension.javaClass.getMethod("getCompileSdk")
                val currentSdk = getCompileSdk.invoke(androidExtension) as? Int

                // If it's less than 34, force it to 37
                if (currentSdk != null && currentSdk < 34) {
                    println("Overriding compileSdk for plugin '${project.name}' from $currentSdk to 37")
                    val setCompileSdk = androidExtension.javaClass.getMethod("setCompileSdk", Int::class.java)
                    setCompileSdk.invoke(androidExtension, 37)
                }
            } catch (e: Exception) {
                // Ignore reflection errors
            }
        }
    }
}

// 2. Set the build directory for subprojects.
subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// 3. APPLY THE EVALUATION DEPENDENCY LAST. This must come after the override is registered.
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}