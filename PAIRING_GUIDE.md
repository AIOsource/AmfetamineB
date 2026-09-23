# Pairing Guide for AmfetamineB

pairing is only needed once. it gives AmfetamineB permission to talk to the local iOS lockdown daemon over the loopback vpn tunnel so it can write theme assets into system cache folders.

---

## method 1: pc helper (easiest, 1-click)

### requirements
- pc (windows / linux) or mac
- usb cable
- python 3.8+

### steps
1. unlock your iphone and plug it into your pc via usb.
2. if your phone asks **Trust This Computer?**, tap **Trust** and enter your passcode.
3. on your pc, open terminal / command prompt in the `pc-helper` folder:
   ```bash
   cd pc-helper
   pip3 install -r requirements.txt
   python3 app.py
   ```
4. the helper window will show: `Connected: iPhone (USB)`.
5. click the **Exploit** button.
6. the helper extracts the pairing record and automatically transfers `aircard_pairing.plist` directly into your AmfetamineB app folder via usb.
7. open AmfetamineB on your phone. the main screen will say `System Ready` and show your pairing file.

---

## method 2: manual pairing file import

if you already have a pairing file from another tool (like cowabunga, nugget, or pymobiledevice3) or want to do it manually:

1. generate a pairing file on your pc:
   ```bash
   pip3 install pymobiledevice3
   pymobiledevice3 lockdown pair
   ```
   on macOS, pairing files are saved in `/var/db/lockdown/<UDID>.plist`.
   on Windows, pairing files are in `C:\ProgramData\Apple\Lockdown\<UDID>.plist`.
   on Linux, pairing files are in `/var/lib/lockdown/<UDID>.plist`.

2. rename that plist file to `aircard_pairing.plist` (or keep its name).
3. send it to your iphone via AirDrop, iCloud Drive, or Telegram.
4. open **AmfetamineB** on your iphone.
5. tap **Settings** (gear icon in top left) -> tap **Import .plist Pairing File**.
6. select the file in the file picker.
7. done. you can also just drop the `.plist` file directly into **On My iPhone -> AmfetamineB** inside the Files app.

---

## troubleshooting

- **phone not detected by pc helper:**
  make sure itunes / apple devices app is installed if on windows (for usb drivers). make sure the screen is unlocked. try another usb port or cable.
- **localdev vpn says inactive:**
  tap **Connect** on the main screen. iOS will ask to add VPN configuration, tap Allow.
- **pairing file missing after reboot:**
  pairing files are stored permanently in the app documents directory. if you delete or reinstall the app, you will need to re-pair.
- **springboard changes not showing up:**
  make sure the LocalDev VPN is connected before hitting Apply. after applying, always tap **Respring** in top right.

