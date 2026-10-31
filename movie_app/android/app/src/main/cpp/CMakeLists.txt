cmake_minimum_required(VERSION 3.22.1)
project(crashhandler)

add_library(crashhandler SHARED crash_handler.cpp)

find_library(log-lib log)
target_link_libraries(crashhandler ${log-lib})
