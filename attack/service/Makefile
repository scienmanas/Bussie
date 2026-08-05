# ?= only sets these if not already set in the environment, so callers can override
CXX      ?= g++
CXXFLAGS ?= -O2 -Wall -Wextra -std=c++17
# --cflags: compiler-facing flags (-I include paths) so #include <dbus/dbus.h> resolves
# --libs:   linker-facing flags (-l/-L) so symbols like dbus_connection_open resolve
PKG_CFLAGS := $(shell pkg-config --cflags dbus-1)
PKG_LIBS   := $(shell pkg-config --libs   dbus-1)

# $@ = target (bussie-service), $< = first prerequisite (src/service.cpp)
bussie-service: src/service.cpp
	$(CXX) $(CXXFLAGS) $(PKG_CFLAGS) -o $@ $< $(PKG_LIBS)

clean:
	rm -f bussie-service

# .PHONY: 'clean' isn't a real file, so this always runs even if a file named clean exists
.PHONY: clean
