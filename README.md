# AmfetamineB (v0.1.4)

all-in-one customization tool for ios 18.0+. lets you theme passcode buttons, customize phone dialer, inject custom art into apple wallet cards, and apply live posterboard wallpapers. works through local pairing and a loopback vpn tunnel.

no jailbreak needed.

---

## what it does

- passcode themer: make custom key slices or download themes directly from the explore tab in 2 clicks.
- phone themer: custom dialer keypad images and fonts.
- wallet cards: put your own custom images on apple wallet passes.
- posterboard: live video wallpapers, tendies descriptors, and carplay wallpapers.
- localdev vpn: routes lockdownd requests locally on device (10.7.0.1).
- oled pure black theme with accent colors in settings.

---

## how to use

1. install `AmfetamineB.ipa` on your iphone using trollstore, sidestore, altstore, sideloadly, or livecontainer.
2. pair your phone with your pc (needed once so the app can talk to lockdownd). see [PAIRING_GUIDE.md](PAIRING_GUIDE.md) for steps.
3. open AmfetamineB on your phone.
4. on the main tab, tap **Connect** under Network to start the LocalDev VPN tunnel.
5. pick whatever you want to customize (Passcode, Phone, Wallet Cards, PosterBoard) and hit Apply.
6. tap **Respring** in top right to reload springboard.

---

## how to pair (quick summary)

you need a pc or mac with python 3 installed.

```bash
cd pc-helper
pip3 install -r requirements.txt
python3 app.py
```

1. plug your iphone into pc with usb cable and unlock your screen (tap "Trust This Computer" if asked).
2. open the pc helper window (it will detect your phone).
3. click **Exploit**.
4. the tool grabs your pairing record and pushes it straight into the app on your phone.
5. done.

for detailed troubleshooting and manual pairing steps, read [PAIRING_GUIDE.md](PAIRING_GUIDE.md).

---

## building from source

requirements:
- mac with xcode 16+
- xcodegen (`brew install xcodegen`)

```bash
# clone repo
git clone https://github.com/AIOsource/AmfetamineB.git
cd AmfetamineB

# generate xcode project
xcodegen generate

# build unsigned ipa
./build-ipa.sh Release
```

the compiled ipa will be in `build/AmfetamineB.ipa`.

---

## credits

- dev: [@N1kotinow](https://t.me/N1kotinow) on telegram
- source: [AIOsource](https://github.com/AIOsource)
- repo: [https://github.com/AIOsource/AmfetamineB](https://github.com/AIOsource/AmfetamineB)
