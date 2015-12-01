# atom-android-debugger package

This is a fork from [https://github.com/xndcn/atom-debugger](https://github.com/xndcn/atom-debugger)

Before debugging, please add your source root directory into the tree-view and start gdbserver from your device:

```
  adb forward tcp:5039 tcp:5039
  adb shell /system/bin/gdbserver --multi localhost:5039
```

Remember to set paths:

![config](https://raw.githubusercontent.com/longseespace/atom-android-debugger/master/config.png?raw=true)

Screenshot:

![screenshot](https://raw.githubusercontent.com/longseespace/atom-android-debugger/master/screenshot.png?raw=true)


## TO DO

* Add `watch` view to display variable value.
