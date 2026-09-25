#!/system/bin/sh
# Set brightness to 4095 when max is reached
# place in /data/adb/service.d/brightness-fix.sh
# if 255 is wrong then use "cat /sys/class/leds/lcd-backlight/brightness" to see what the "max" the cc slider can go up to
# this is a very ugly fix but it works
while true; do
  current=$(cat /sys/class/leds/lcd-backlight/brightness)
  if [ "$current" -eq 255 ]; then
    echo 4095 > /sys/class/leds/lcd-backlight/brightness
  fi
  sleep 1
done   
