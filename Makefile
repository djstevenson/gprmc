.PHONY: cleanup run main text

run: cleanup text main

cleanup:
	rm -rf frames
	mkdir frames

main:
	rm -rf frames/telemetry
	mkdir -p frames/telemetry
	date
	carton exec -- ./clip_times.pl /Users/davids/Desktop/transport/Test\ footage/A338\ Northbound/NextBase/front | carton exec -- ./gprmc.pl
	date
	for x in 0 1 2 3 4 5 6 7 8 9 a b c d e f; do \
		node render-frames.js "frames/telemetry" "$$x" & \
	done; \
	wait
	date
	ffmpeg -framerate 30 -pattern_type glob -i 'frames/telemetry/gauges*.png' -vf "scale=1920:1080:flags=lanczos" -c:v prores_ks -profile:v 3 -pix_fmt yuv422p10le 'frames/telemetry/gauges.mov'
	date

text:
	rm -rf frames/text
	date
	cat A4074.csv | carton exec -- ./make_text.pl
	date
	for d in frames/text/*; do \
		for x in 0 1 2 3 4 5 6 7 8 9; do \
			node render-frames.js "$$d" "$$x" & \
		done; \
		wait; \
		date; \
		ffmpeg -framerate 30 -pattern_type glob -i "$$d/*.png" -vf "scale=1920:1080:flags=lanczos" -c:v prores_ks -profile:v 4 -pix_fmt yuva444p10le "$$d.mov"; \
	done
	date
