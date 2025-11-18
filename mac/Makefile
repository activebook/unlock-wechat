CC=clang
CFLAGS=-I. -Wall
LDFLAGS=-framework AppKit -framework Foundation

TARGET=UnLockWeChat.app/Contents/MacOS/unlock-wechat-app

all: $(TARGET) icon

$(TARGET): unlock-wechat-app.o
	$(CC) $(LDFLAGS) -o $@ unlock-wechat-app.o

unlock-wechat-app.o: unlock-wechat-app.m
	$(CC) $(CFLAGS) -c unlock-wechat-app.m -o unlock-wechat-app.o

icon: UnLockWeChat.app/Contents/Resources/icon.icns

UnLockWeChat.app/Contents/Resources/icon.icns: icon.icns
	mkdir -p UnLockWeChat.app/Contents/Resources
	cp $< $@

clean:
	rm -f *.o $(TARGET)

.PHONY: clean all icon
