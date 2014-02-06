# Cylinder

The free software alternative to Barrel

![LOL](http://i.imgur.com/JhSytf7m.png)

## Why?

Because I don't want to pay $2 for something that takes a few hours to make

## Todo list

* ~~Make proof-of-concept cycript 'script'~~
* ~~Port it to a Mobilesubstrate tweak~~
* Add Lua bindings
* Add preferences bundle
* Add more example Barrel thingies
* Release!

## How to use

### Building

If you have Xcode installed on your computer (or some other way to compile for iOS), cd into substrate and make. SCP it to the phone and boom you're done.

### Cycript

If you don't have any developer tools installed, you'll need [cycript](http://cycript.org) 0.9.5+ installed. Just copy these files in the cycript folder to your device and

```
./runme.sh
```

If that doesn't work, then do

```
cycript -p SpringBoard
```

and paste the contents in line-by-line. sorry, this is a bug with cycript :(

## License

[GNU GPL](https://github.com/rweichler/cylinder/blob/master/LICENSE), unless otherwise stated in the files themselves.
