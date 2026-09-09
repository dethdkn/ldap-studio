# Builds build/libldapstudio.a — the native core the SwiftUI app links.
#
# Standalone:  make            (builds for the host arch)
# From Xcode:  the "Build C Core" script phase runs `make`, passing ARCHS,
#              MACOSX_DEPLOYMENT_TARGET and SDKROOT through the environment.
#
# Depends on the Homebrew formulae in ../Brewfile (openldap, openssl@3,
# libxcrypt) — all keg-only, so their include paths are added explicitly.

SRC := $(wildcard src/*.c)
HDR := $(wildcard src/*.h include/*.h)
OBJ := $(SRC:%.c=build/%.o)
LIB := build/libldapstudio.a

CC ?= clang
BREW ?= brew

# clang-format ships with the Command Line Tools; clang-tidy comes from a
# Homebrew llvm keg. Fall back to those if they're not on PATH; override
# with `make format CLANG_FORMAT=/path/to/clang-format`.
CLANG_FORMAT ?= $(firstword $(shell command -v clang-format 2>/dev/null) \
                            $(shell xcrun -f clang-format 2>/dev/null) clang-format)
CLANG_TIDY   ?= $(firstword $(shell command -v clang-tidy 2>/dev/null) \
                            $(wildcard /opt/homebrew/opt/llvm*/bin/clang-tidy) clang-tidy)

OPENLDAP  := $(shell $(BREW) --prefix openldap 2>/dev/null)
OPENSSL   := $(shell $(BREW) --prefix openssl@3 2>/dev/null)
LIBXCRYPT := $(shell $(BREW) --prefix libxcrypt 2>/dev/null)

ifeq ($(OPENLDAP),)
$(error openldap not found — run `brew bundle` from the repo root)
endif

ifeq ($(OPENSSL),)
$(error openssl@3 not found — run `brew bundle` from the repo root)
endif

ifeq ($(LIBXCRYPT),)
$(error libxcrypt not found — run `brew bundle` from the repo root)
endif

ARCHS ?= $(shell uname -m)
ARCHFLAGS := $(foreach a,$(ARCHS),-arch $(a))

ifdef MACOSX_DEPLOYMENT_TARGET
MINFLAG := -mmacosx-version-min=$(MACOSX_DEPLOYMENT_TARGET)
endif

# Xcode sets SDKROOT; standalone, resolve it so compile_commands.json is
# self-contained for tools (clang-tidy) that lack Apple clang's baked-in SDK.
SDKROOT ?= $(shell xcrun --show-sdk-path 2>/dev/null)
ifneq ($(SDKROOT),)
SYSROOT := -isysroot $(SDKROOT)
endif

CFLAGS ?= -std=c11 -O2 -Wall -Wextra -fno-common
CPPFLAGS += -Iinclude -Isrc \
            -I$(OPENLDAP)/include \
            -I$(OPENSSL)/include \
            -I$(LIBXCRYPT)/include

all: $(LIB)

$(LIB): $(OBJ)
	@mkdir -p $(dir $@)
	libtool -static -o $@ $(OBJ)

# -MMD -MP emits a build/src/foo.d listing every header foo.c pulls in, so
# editing e.g. ldapstudio.h forces the affected .o files to rebuild.
build/%.o: %.c
	@mkdir -p $(dir $@)
	$(CC) $(ARCHFLAGS) $(MINFLAG) $(SYSROOT) $(CFLAGS) $(CPPFLAGS) -MMD -MP -c $< -o $@

-include $(OBJ:.o=.d)

clean:
	rm -rf build

# Regenerate core/compile_commands.json for editors / clangd (needs `bear`).
compdb:
	$(MAKE) clean
	bear --output compile_commands.json -- $(MAKE) all

# Reformat all C sources/headers in place, per ../.clang-format.
format:
	$(CLANG_FORMAT) -i $(SRC) $(HDR)

# Fail if anything isn't formatted (for CI / pre-commit).
format-check:
	$(CLANG_FORMAT) --dry-run --Werror $(SRC) $(HDR)

# Static analysis per ../.clang-tidy. Needs compile_commands.json.
tidy:
	@test -f compile_commands.json || { echo "run 'make compdb' first" >&2; exit 1; }
	$(CLANG_TIDY) -p . $(SRC)

.PHONY: all clean compdb format format-check tidy
