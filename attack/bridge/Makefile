CXX      ?= g++
CXXFLAGS ?= -O2 -Wall -Wextra -std=c++17
PKG_CFLAGS := $(shell pkg-config --cflags dbus-1)
PKG_LIBS   := $(shell pkg-config --libs   dbus-1)

bussie-bridge: src/bridge.cpp
	$(CXX) $(CXXFLAGS) $(PKG_CFLAGS) -o $@ $< $(PKG_LIBS)

clean:
	rm -f bussie-bridge

# clean isn't a real file we produce, so mark it .PHONY: this stops make from
# skipping the recipe if a file literally named "clean" ever exists on disk.
.PHONY: clean
