cmake_minimum_required(VERSION 3.18.1)

project("serial_port")

# Builds libserial_port.so consumed by android_serialport_api.SerialPort
# (System.loadLibrary("serial_port")).
add_library(
    serial_port
    SHARED
    SerialPort.c
)

# Link against Android's log library (used by the LOGI/LOGE macros).
find_library(log-lib log)
target_link_libraries(serial_port ${log-lib})
