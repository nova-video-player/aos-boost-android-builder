### Boost android builder

boost as used by [nova](https://github.com/nova-video-player/aos-AVP).
Please see upstream Gist from enh: 

https://gist.github.com/enh/b2dc8e2cbbce7fffffde2135271b10fd

Typical usage:
```
bash ./build.sh -a $ARCH
```

$ARCH can be either: arm arm64 x86 x86_64

Requirements:
- a recent NDK (tested with r19-beta2)
- some dev tools
- free disk space (about 6GB)
