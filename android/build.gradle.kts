allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// ---------------------------------------------------------------------------
// compileSdk floor for plugin subprojects.
//
// agora_rtc_engine still declares compileSdk 31, but the AndroidX libraries it
// depends on (fragment 1.7.1, window 1.2.0) require their consumers to compile
// against API 34 or later. Gradle rejects the mismatch in checkAarMetadata, so
// the build fails before it ever reaches our own code.
//
// Raising the floor here rather than forking the plugin keeps the workaround in
// one place and covers any other plugin that lags behind.
//
// Two things about this block are deliberate:
//
//  1. It must be registered BEFORE the `evaluationDependsOn(":app")` block
//     below. That call forces evaluation, and Gradle refuses a later
//     afterEvaluate on an already-evaluated project.
//  2. It uses reflection rather than the typed Android DSL. The extension type
//     has changed across AGP majors (this project is on AGP 9.1.0), so
//     reflection keeps the fix from breaking on the next upgrade. Failures are
//     swallowed by runCatching because a plugin that does not expose
//     compileSdk simply does not need the floor.
// ---------------------------------------------------------------------------
val pluginCompileSdkFloor = 37

subprojects {
    afterEvaluate {
        val androidExtension = extensions.findByName("android") ?: return@afterEvaluate
        runCatching {
            val methods = androidExtension.javaClass.methods
            val current = methods
                .firstOrNull { it.name == "getCompileSdk" && it.parameterCount == 0 }
                ?.invoke(androidExtension) as? Int
                ?: return@runCatching

            if (current < pluginCompileSdkFloor) {
                methods
                    .firstOrNull { it.name == "setCompileSdk" && it.parameterCount == 1 }
                    ?.invoke(androidExtension, pluginCompileSdkFloor)
                logger.lifecycle(
                    "compileSdk floor: raised ${project.name} from $current to $pluginCompileSdkFloor"
                )
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
