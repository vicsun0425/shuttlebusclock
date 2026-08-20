.PHONY: all gen open clean

all: gen open

gen:
	@command -v xcodegen >/dev/null 2>&1 || { echo "❌ xcodegen 未安装,请先运行: brew install xcodegen"; exit 1; }
	xcodegen generate
	@echo "✅ 已生成 ShuttleBusClock.xcodeproj"

open: gen
	open ShuttleBusClock.xcodeproj

clean:
	rm -rf ShuttleBusClock.xcodeproj
	rm -rf ~/Library/Developer/Xcode/DerivedData/ShuttleBusClock-*