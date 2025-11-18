CC=clang
CFLAGS=-I. -Wall
LDFLAGS=-framework AppKit -framework Foundation -framework Security

TARGET=UnLockWeChat.app/Contents/MacOS/unlock-wechat-app

all: $(TARGET) icon key info

$(TARGET): unlock-wechat-app.o license.o
	mkdir -p UnLockWeChat.app/Contents/MacOS
	$(CC) $(LDFLAGS) -o $@ unlock-wechat-app.o license.o

unlock-wechat-app.o: unlock-wechat-app.m
	$(CC) $(CFLAGS) -c unlock-wechat-app.m -o unlock-wechat-app.o

license.o: license.m
	$(CC) $(CFLAGS) -c license.m -o license.o

icon: UnLockWeChat.app/Contents/Resources/icon.icns

UnLockWeChat.app/Contents/Resources/icon.icns: icon.icns
	mkdir -p UnLockWeChat.app/Contents/Resources
	cp $< $@

key: UnLockWeChat.app/Contents/Resources/public.key

UnLockWeChat.app/Contents/Resources/public.key: public.key
	mkdir -p UnLockWeChat.app/Contents/Resources
	cp $< $@

info: UnLockWeChat.app/Contents/Info.plist

UnLockWeChat.app/Contents/Info.plist: Info.plist
	mkdir -p UnLockWeChat.app/Contents
	cp $< $@

clean:
	rm -f *.o $(TARGET)

.PHONY: clean all icon key info
