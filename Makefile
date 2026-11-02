BEEBASM = ./beebasm
SRC = caterpillar.asm
OUT = caterpillar.ssd

JSBEEB_DIR = $(HOME)/.local/share/jsbeeb
JSBEEB_URL = http://localhost:5173/\?disc1=caterpillar.ssd\&autoboot

.PHONY: all clean run serve web

all: $(OUT)

$(OUT): $(SRC) caterpillar.bas !BOOT
	$(BEEBASM) -i $(SRC) -do $(OUT) -opt 3 -v

run: $(OUT)
	@ln -sf $(CURDIR)/$(OUT) $(JSBEEB_DIR)/public/discs/$(OUT)
	@if ! lsof -i :5173 -sTCP:LISTEN >/dev/null 2>&1; then \
		cd $(JSBEEB_DIR) && npm start & \
		sleep 3; \
	fi
	@open $(JSBEEB_URL)

# index.html as GitHub Pages serves it, at http://localhost:8086/
serve: $(OUT)
	python3 -m http.server 8086

# web/: the page's emulator, bundled from jsbeeb
web:
	JSBEEB_DIR=$(JSBEEB_DIR) node tools/web/build.mjs

clean:
	rm -f $(OUT)
