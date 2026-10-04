/* Stands in for Node in tests: prints each argument as UTF-8 on its own line, then exits with PRINT_ARGS_STATUS, if
 * set.
 *
 * Build on Windows with RubyInstaller's toolchain: ridk exec gcc -O2 -s -municode -o print_args.exe print_args.c
 */
#include <fcntl.h>
#include <io.h>
#include <stdio.h>
#include <stdlib.h>
#include <windows.h>

int wmain(int argc, wchar_t *argv[]) {
  _setmode(_fileno(stdout), _O_BINARY);

  for (int i = 1; i < argc; i++) {
    int size = WideCharToMultiByte(CP_UTF8, 0, argv[i], -1, NULL, 0, NULL, NULL);
    char *arg = malloc(size);
    WideCharToMultiByte(CP_UTF8, 0, argv[i], -1, arg, size, NULL, NULL);
    puts(arg);
    free(arg);
  }

  const wchar_t *status = _wgetenv(L"PRINT_ARGS_STATUS");
  return status ? _wtoi(status) : 0;
}
