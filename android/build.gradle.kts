allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
// Algunos plugins se quedaron con un compileSdk viejo. fluttertoast 8.2.14
// compila contra Android 33, y las androidx que hoy llegan con el resto de las
// dependencias (fragment 1.7, window 1.2) exigen 34 o mas: AGP corta el build
// en :fluttertoast:checkDebugAarMetadata. A los que quedan por debajo de 34 se
// les pone el compileSdk de la app, que es el que dicta Flutter.
//
// compileSdk solo decide contra que API se COMPILA: no toca minSdk ni
// targetSdk, asi que en el telefono no cambia nada.
//
// Tiene que ir ANTES del bloque de evaluationDependsOn: ese evalua :app en el
// acto, y un afterEvaluate registrado sobre un proyecto ya evaluado no corre
// (Gradle lo rechaza).
subprojects {
    afterEvaluate {
        val android = extensions.findByName("android")
            as? com.android.build.gradle.BaseExtension ?: return@afterEvaluate
        val deLaApp = (rootProject.project(":app").extensions.findByName("android")
            as? com.android.build.gradle.BaseExtension)?.compileSdkVersion
            ?: return@afterEvaluate
        val nivel = android.compileSdkVersion?.removePrefix("android-")?.toIntOrNull()
        if (nivel != null && nivel < 34) {
            android.compileSdkVersion(deLaApp)
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
