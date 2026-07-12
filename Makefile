.PHONY: run

run:
	rm -rf gauges.mp4 gauges.mov output/* frames/* render-frames/*
	exiftool -ee -n 260627_175730_005_FH.MP4 | carton exec -- ./gprmc.pl
	for d in output/[0-9][0-9]; do \
		node render-frames.js "$$d" "frames/$$(basename "$$d")" & \
	done; \
	wait
	mkdir -p render-frames
	n=1; find frames -type f -name '*.png' | sort | while read -r f; do ln -sf "$$PWD/$$f" "$$(printf 'render-frames/frame%06d.png' $$n)"; n=$$((n + 1)); done
	ffmpeg -framerate 30 -i render-frames/frame%06d.png -c:v prores_ks -profile:v 3 -pix_fmt yuv422p10le gauges.mov
