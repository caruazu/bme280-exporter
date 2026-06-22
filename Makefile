BINARY  = bme280-reader
SRCDIR  = src
BINDIR  = bin

CC     ?= gcc
CFLAGS  = -std=c11 -Wall -Wextra -Wpedantic \
          -D_FORTIFY_SOURCE=2 -fstack-protector-strong \
          -fPIE -pie \
          -O2
LDFLAGS = -Wl,-z,relro -Wl,-z,now

.PHONY: all clean

all: $(BINDIR)/$(BINARY)

$(BINDIR)/$(BINARY): $(SRCDIR)/hello-world.c | $(BINDIR)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $<

$(BINDIR):
	mkdir -p $@

clean:
	rm -f $(BINDIR)/$(BINARY)
