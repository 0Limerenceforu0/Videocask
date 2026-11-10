#include <jni.h>
#include <signal.h>
#include <unistd.h>
#include <fcntl.h>
#include <time.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <cstdio>
#include <string>
#include <cstring>
#include <dlfcn.h>
#include <android/log.h>
#include <unwind.h>

// 把崩溃调用栈直接写到应用外部文件目录下的 crash_*.txt，供手机端直接提取，
// 无需 adb / 电脑。崩溃栈为 PC + .so 偏移，后续可用 NDK addr2line 还原符号。

static std::string g_log_dir;
static volatile sig_atomic_t g_in_handler = 0;

static const char* SignalName(int sig) {
  switch (sig) {
    case SIGSEGV: return "SIGSEGV";
    case SIGABRT: return "SIGABRT";
    case SIGBUS:  return "SIGBUS";
    case SIGILL:  return "SIGILL";
    case SIGFPE:  return "SIGFPE";
    default:      return "UNKNOWN";
  }
}

struct BacktraceState {
  void** current;
  void** end;
};

static _Unwind_Reason_Code UnwindCallback(struct _Unwind_Context* context, void* arg) {
  BacktraceState* state = reinterpret_cast<BacktraceState*>(arg);
  uintptr_t pc = _Unwind_GetIP(context);
  if (pc == 0) return _URC_NO_REASON;
  if (state->current >= state->end) return _URC_END_OF_STACK;
  *state->current++ = reinterpret_cast<void*>(pc);
  return _URC_NO_REASON;
}

static size_t CaptureBacktrace(void** buffer, size_t max) {
  BacktraceState state = { buffer, buffer + max };
  _Unwind_Backtrace(UnwindCallback, &state);
  return static_cast<size_t>(state.current - buffer);
}

static void EnsureDir(const char* path) {
  // 逐级创建目录（path 末尾不含分隔符）。
  std::string p(path);
  for (size_t i = 1; i < p.size(); ++i) {
    if (p[i] == '/') {
      std::string sub = p.substr(0, i);
      mkdir(sub.c_str(), 0700);
    }
  }
  mkdir(p.c_str(), 0700);
}

static void WriteAll(int fd, const char* data, size_t len) {
  size_t off = 0;
  while (off < len) {
    ssize_t n = write(fd, data + off, len - off);
    if (n <= 0) break;
    off += static_cast<size_t>(n);
  }
}

// 读取同目录下的硬解状态快照（由 Dart 侧在设置 hwdec 时写入）。
// 目的：原生崩溃时能立刻判断「这次崩溃是否发生在硬解会话中」，
// 从而把硬解相关崩溃自动计数并触发降档（而不是靠用户口述）。
static void AppendHwDecState(int fd, const std::string& dir) {
  std::string path = dir + "/hwdec_state.txt";
  int sfd = open(path.c_str(), O_RDONLY);
  if (sfd < 0) return;
  char buf[256];
  ssize_t n = read(sfd, buf, sizeof(buf) - 1);
  close(sfd);
  if (n <= 0) return;
  buf[n] = '\0';
  const char* header = "hwdec-state: ";
  WriteAll(fd, header, strlen(header));
  WriteAll(fd, buf, static_cast<size_t>(n));
  WriteAll(fd, "\n", 1);
}

// 读取同目录下的 fd 运行时状态快照（由 Dart 侧周期写入 fd_state.txt）。
// 目的：原生崩溃时立刻能判断「是不是撞上文件句柄耗尽」——
// fd 打满会让系统层的 MediaCodec 内部打开文件失败并 SIGSEGV，
// 没有这一行就只能靠日志正文反推。
static void AppendFdState(int fd, const std::string& dir) {
  std::string path = dir + "/fd_state.txt";
  int sfd = open(path.c_str(), O_RDONLY);
  if (sfd < 0) return;
  char buf[512];
  ssize_t n = read(sfd, buf, sizeof(buf) - 1);
  close(sfd);
  if (n <= 0) return;
  buf[n] = '\0';
  const char* header = "fd-state: ";
  WriteAll(fd, header, strlen(header));
  WriteAll(fd, buf, static_cast<size_t>(n));
  WriteAll(fd, "\n", 1);
}

static void CrashSignalHandler(int sig) {
  if (g_in_handler) _exit(71);  // 重入保护
  g_in_handler = 1;

  const int kMax = 64;
  void* frames[kMax];
  size_t count = CaptureBacktrace(frames, kMax);

  char stamp[64];
  time_t now = time(nullptr);
  struct tm tmv;
  localtime_r(&now, &tmv);
  strftime(stamp, sizeof(stamp), "%Y%m%d_%H%M%S", &tmv);

  std::string dir = g_log_dir;
  if (dir.empty()) dir = "/sdcard/Android/data/com.example.movie_app/files/videocask_logs";
  EnsureDir(dir.c_str());

  std::string file = dir + "/crash_" + stamp + ".txt";
  int fd = open(file.c_str(), O_CREAT | O_WRONLY | O_TRUNC, 0600);
  if (fd < 0) _exit(72);

  char header[512];
  int hl = snprintf(header, sizeof(header),
      "Videocask native crash: signal %d (%s)\n"
      "time: %s\n"
      "process: com.example.movie_app\n"
      "frames: %zu\n"
      "PC format: <so-path>  base+offset  (addr2line -e <so> <offset>)\n"
      "----------------------------------------\n",
      sig, SignalName(sig), stamp, count);
  WriteAll(fd, header, static_cast<size_t>(hl));

  char line[1024];
  for (size_t i = 0; i < count; ++i) {
    Dl_info info;
    memset(&info, 0, sizeof(info));
    dladdr(frames[i], &info);
    const char* fname = (info.dli_fname ? info.dli_fname : "???");
    uintptr_t base = reinterpret_cast<uintptr_t>(info.dli_fbase);
    uintptr_t off = reinterpret_cast<uintptr_t>(frames[i]) - base;
    const char* sym = (info.dli_sname ? info.dli_sname : "?");
    int ll = snprintf(line, sizeof(line),
        "#%02zu  %p  %s  0x%lx  (%s)\n",
        i, frames[i], fname, static_cast<unsigned long>(off), sym);
    WriteAll(fd, line, static_cast<size_t>(ll));
  }
  fsync(fd);
  // 附上硬解状态快照：便于事后判断崩溃是否与硬解相关。
  AppendHwDecState(fd, dir);
  // 附上 fd 运行时状态：判断这次崩溃是不是撞上「文件句柄耗尽」。
  // 2026-10-22 真机崩溃：fd=32669/32768（99.7% 满）时崩在系统硬解路径
  // （MediaCodec::handleOutputFormatChangeIfNeeded），当时崩溃文件里没有
  // fd 数，只能靠日志正文反推。
  AppendFdState(fd, dir);
  close(fd);

  __android_log_print(ANDROID_LOG_ERROR, "VideocaskCrash",
      "native crash signal %d written to %s", sig, file.c_str());

  // 直接退出，让进程干净死亡（已写好可读栈）。
  _exit(70);
}

extern "C" JNIEXPORT void JNICALL
Java_com_example_movie_1app_CrashHandler_nativeInstall(JNIEnv* env, jobject, jstring dir) {
  // 总是（重新）注册：播放器后端（media_kit/libmpv）可能在 Player 创建后安装自己的信号
  // 处理器并覆盖掉我们的，因此允许重复调用以「抢回」注册权（谁后注册谁赢）。
  if (dir) {
    const char* c = env->GetStringUTFChars(dir, nullptr);
    if (c) { g_log_dir = c; env->ReleaseStringUTFChars(dir, c); }
  }
  struct sigaction sa;
  memset(&sa, 0, sizeof(sa));
  sa.sa_handler = CrashSignalHandler;
  sigemptyset(&sa.sa_mask);
  sa.sa_flags = SA_RESTART;
  sigaction(SIGSEGV, &sa, nullptr);
  sigaction(SIGABRT, &sa, nullptr);
  sigaction(SIGBUS, &sa, nullptr);
  sigaction(SIGILL, &sa, nullptr);
  sigaction(SIGFPE, &sa, nullptr);
  // 不缓存是否已安装：每次调用都重新注册，确保覆盖后注册的播放器后端处理器。
}
