/*
 * Native side of android-serialport-api.
 *
 * Opens /dev/ttyS* via standard POSIX open(), configures baud rate / 8N1 /
 * no-flow-control with termios, and returns a FileDescriptor jobject that
 * Java can wrap with FileInputStream/FileOutputStream.
 *
 * Original Apache 2.0 source by cepr; trimmed and adapted for inclusion
 * in the VMFS kiosk APK.
 */

#include <termios.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <string.h>
#include <jni.h>

#include <android/log.h>
#define LOG_TAG "SerialPort"
#define LOGI(fmt, args...) __android_log_print(ANDROID_LOG_INFO,  LOG_TAG, fmt, ##args)
#define LOGE(fmt, args...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, fmt, ##args)

static speed_t getBaudrate(jint baudrate) {
    switch (baudrate) {
        case 0:       return B0;
        case 50:      return B50;
        case 75:      return B75;
        case 110:     return B110;
        case 134:     return B134;
        case 150:     return B150;
        case 200:     return B200;
        case 300:     return B300;
        case 600:     return B600;
        case 1200:    return B1200;
        case 1800:    return B1800;
        case 2400:    return B2400;
        case 4800:    return B4800;
        case 9600:    return B9600;
        case 19200:   return B19200;
        case 38400:   return B38400;
        case 57600:   return B57600;
        case 115200:  return B115200;
        case 230400:  return B230400;
        case 460800:  return B460800;
        case 500000:  return B500000;
        case 576000:  return B576000;
        case 921600:  return B921600;
        case 1000000: return B1000000;
        case 1152000: return B1152000;
        case 1500000: return B1500000;
        case 2000000: return B2000000;
        case 2500000: return B2500000;
        case 3000000: return B3000000;
        case 3500000: return B3500000;
        case 4000000: return B4000000;
        default:      return -1;
    }
}

JNIEXPORT jobject JNICALL
Java_android_1serialport_1api_SerialPort_open(JNIEnv *env, jclass thiz,
                                              jstring path, jint baudrate, jint flags) {
    int fd;
    speed_t speed;
    jobject mFileDescriptor;

    speed = getBaudrate(baudrate);
    if (speed == (speed_t) -1) {
        LOGE("Invalid baudrate %d", baudrate);
        return NULL;
    }

    const char *path_utf = (*env)->GetStringUTFChars(env, path, JNI_FALSE);
    LOGI("Opening serial port %s with flags 0x%x", path_utf, O_RDWR | flags);
    fd = open(path_utf, O_RDWR | flags);
    LOGI("open() fd = %d", fd);
    (*env)->ReleaseStringUTFChars(env, path, path_utf);

    if (fd == -1) {
        LOGE("Cannot open port");
        return NULL;
    }

    struct termios cfg;
    LOGI("Configuring serial port");
    if (tcgetattr(fd, &cfg)) {
        LOGE("tcgetattr() failed");
        close(fd);
        return NULL;
    }

    cfmakeraw(&cfg);
    cfsetispeed(&cfg, speed);
    cfsetospeed(&cfg, speed);

    // 8N1, no flow control
    cfg.c_cflag |= (CLOCAL | CREAD);
    cfg.c_cflag &= ~CSIZE;
    cfg.c_cflag |= CS8;
    cfg.c_cflag &= ~PARENB;
    cfg.c_cflag &= ~CSTOPB;
    cfg.c_cflag &= ~CRTSCTS;

    if (tcsetattr(fd, TCSANOW, &cfg)) {
        LOGE("tcsetattr() failed");
        close(fd);
        return NULL;
    }

    // Wrap raw fd into a java.io.FileDescriptor
    jclass cFileDescriptor = (*env)->FindClass(env, "java/io/FileDescriptor");
    jmethodID iFileDescriptor = (*env)->GetMethodID(env, cFileDescriptor, "<init>", "()V");
    jfieldID descriptorID = (*env)->GetFieldID(env, cFileDescriptor, "descriptor", "I");
    mFileDescriptor = (*env)->NewObject(env, cFileDescriptor, iFileDescriptor);
    (*env)->SetIntField(env, mFileDescriptor, descriptorID, (jint) fd);

    return mFileDescriptor;
}

JNIEXPORT void JNICALL
Java_android_1serialport_1api_SerialPort_close(JNIEnv *env, jobject thiz) {
    jclass SerialPortClass = (*env)->GetObjectClass(env, thiz);
    jclass FileDescriptorClass = (*env)->FindClass(env, "java/io/FileDescriptor");

    jfieldID mFdID = (*env)->GetFieldID(env, SerialPortClass, "mFd",
                                        "Ljava/io/FileDescriptor;");
    jfieldID descriptorID = (*env)->GetFieldID(env, FileDescriptorClass, "descriptor", "I");

    jobject mFd = (*env)->GetObjectField(env, thiz, mFdID);
    jint descriptor = (*env)->GetIntField(env, mFd, descriptorID);

    LOGI("close() called on fd %d", descriptor);
    close(descriptor);
}
