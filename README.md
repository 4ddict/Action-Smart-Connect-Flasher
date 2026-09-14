# 📷 LSC 3215672.2 Decloud Wizard

**Turn the €9.95 Action LSC Smart Connect indoor camera into a local RTSP camera — without needing to know Telnet, MTD flash layouts, cross-compilers, or Linux device names.**

> ✅ Designed for **Action LSC Smart Connect 3215672.2 / SI B26101**  
> 📡 Local 1080p RTSP via `ak_rtsp`  
> ☁️ Removes the Tuya `anyka_ipc` cloud application from the APP partition  
> 💾 Creates a full stock firmware backup before flashing  
> 🐧 Interactive installer for Linux

---

## 🚀 Quick Install

Run this on your Linux computer:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/4ddict/LSC-3215672-Decloud-Wizard/main/install.sh)
```

That is all you need to download manually. The wizard downloads its helper files and the required upstream projects automatically.

**Do not run the complete wizard with `sudo`.** It will ask for your sudo password only when it needs to format/mount the SD card or install packages.

---

## ✨ What the wizard does

The installer is deliberately written for people who have never modified an IP camera before.

It walks you through the complete process using numbered choices and plain-English instructions:

1. 🔎 **Confirm the camera model** — refuses to continue for the wrong article number.
2. 🏷️ **Name the camera** — for example `Front Door` → `front-door`.
3. 🧰 **Check your computer** — installs missing build/tools where supported.
4. 📶 **Ask for Wi-Fi details** — password is hidden and entered twice for verification.
5. 💾 **Choose the microSD card** — shown as an easy numbered list with size/model information.
6. 🛟 **Back up all 8 MTD partitions** before anything is flashed.
7. 📡 **Save Wi-Fi permanently** so the finished camera boots without the SD card.
8. 🏗️ **Build your own cloud-free firmware** from the APP dump of your camera.
9. ⚡ **Flash + read-back verify every 4 KiB block** of the APP partition.
10. ✅ **Check the final RTSP service** and display the stream URL.

A typo or wrong menu choice does **not** terminate the installer. It simply asks again.

---

## 🖥️ Example

```text
╔══════════════════════════════════════════════════════════════╗
║              LSC 3215672.2 DECLOUD WIZARD                  ║
║              Tuya cloud  ➜  Local RTSP                     ║
╚══════════════════════════════════════════════════════════════╝
Beginner-friendly installer for the Action LSC Smart Connect camera
Anyka AK3918AV130 • ak_rtsp • Linux

Version 0.2.0

────────────────────────────────────────────────────────────
[1/8] Camera identification
────────────────────────────────────────────────────────────

? Camera name: Front Door
✔ Camera name saved as 'front-door'.

────────────────────────────────────────────────────────────
[3/8] Wi-Fi setup
────────────────────────────────────────────────────────────

? Wi-Fi SSID: MyWiFi
? Wi-Fi password: ********
? Wi-Fi password again: ********
✔ Wi-Fi password confirmed.
```

---

## 📦 What you need

| Item | Requirement |
| --- | --- |
| Camera | **LSC Smart Connect 3215672.2 / SI B26101** |
| Computer | Linux PC/laptop |
| microSD | Any small card is sufficient; its contents will be erased |
| Wi-Fi | 2.4 GHz network |
| Network | Computer and camera must be able to reach each other locally |

The wizard currently supports dependency installation on **Arch/CachyOS**, **Debian/Ubuntu** and **Fedora-family** systems where the required packages are available.

---

## ⚠️ Check the model before you start

This installer is for:

```text
Art. No. 3215672.2
SI B26101
SoC: Anyka AK3918AV130
```

It is **not** for:

```text
3215672
3215672.1
```

Those revisions use different hardware/firmware. The wizard asks for the article number and also verifies the exact MTD partition map on the camera before allowing a flash.

---

## 🧠 What changes on the camera?

The camera keeps its original:

- U-Boot bootloader
- Linux kernel
- hardware drivers
- root filesystem
- CONFIG partition

The **APP** partition is rebuilt from your own stock dump. The original Tuya/LSC `anyka_ipc` application is removed and replaced by the lightweight local `ak_rtsp` application.

The expected flash map is:

```text
mtd0: 00032000 00001000 "UBOOT"
mtd1: 00001000 00001000 "ENV"
mtd2: 00001000 00001000 "ENVBK"
mtd3: 00010000 00001000 "DTB"
mtd4: 00180000 00001000 "KERNEL"
mtd5: 000fc000 00001000 "ROOTFS"
mtd6: 00040000 00001000 "CONFIG"
mtd7: 00500000 00001000 "APP"
```

If the layout differs, the wizard stops **before writing anything**.

---

## 🛟 Automatic backup

Before modifying the camera, the wizard dumps and verifies all eight original MTD partitions.

Backups are stored per camera name, for example:

```text
~/.cache/lsc-3215672-decloud-wizard/backups/front-door/20260914_153000/
```

This is useful when modifying several cameras. Give each camera a unique name such as:

```text
front-door
backyard
garage
hallway
```

Keep these backups somewhere safe.

---

## 📡 RTSP

After the final boot, the camera should be reachable without an SD card.

```text
rtsp://<camera-ip>:554/
```

The server is path-agnostic, so this also works:

```text
rtsp://<camera-ip>:554/main_ch
```

You can use the stream with software such as **Frigate, Scrypted, Home Assistant, VLC, ffmpeg or go2rtc**.

For multiple cameras, create a DHCP reservation for each camera in your router. The wizard also changes the DHCP hostname to the camera name you entered during setup.

---

## 🔐 Wi-Fi handling

The installer:

- hides the Wi-Fi password while you type;
- asks for it twice;
- stores the temporary credentials on the SD card during installation;
- persists the working `wpa_supplicant` configuration to the camera's CONFIG partition;
- does **not** intentionally upload your Wi-Fi credentials anywhere.

After installation, reformat the SD card because it contains both your Wi-Fi setup files and your private stock firmware dump.

Never commit SD-card contents, firmware dumps, or Wi-Fi configuration files to GitHub.

---

## 🧪 Flash safety checks

Before writing `mtd7`, the camera-side flash script verifies:

- exact supported MTD layout;
- stock APP backup exists and is exactly 5 MiB;
- custom APP image is exactly 5 MiB;
- current camera APP MD5 still matches the backup created in Stage 1;
- `flash_tool` is present.

The image is then erased/written directly to SPI NOR and every 4 KiB block is read back and verified.

A successful run ends with a message similar to:

```text
VERIFICATION SUCCESSFUL
0/1280 chunks needed at least one retry
Flashing and verification completed successfully
```

Only after the wizard has confirmed success should the camera be power-cycled.

---

## 💡 Stage 1 notes

During the first camera boot with the prepared SD card:

- the **blue LED may continue blinking**;
- the factory voice prompt is intentionally muted, so you will normally **not hear the Chinese factory-mode message**;
- leave the camera powered for the full period shown by the wizard.

The wizard checks the SD card afterwards and will tell you whether Stage 1 actually succeeded.

---

## 🛠️ Troubleshooting

### Stage 1 says it did not complete

The most common cause is an incorrect Wi-Fi SSID or password. The wizard lets you re-enter the Wi-Fi details and retry without starting over.

### The camera gets a different IP address

That is normal with DHCP. Check your router's client list. After installation, creating a DHCP reservation is recommended.

### The camera is online but the wizard cannot reach maintenance port 24

Make sure the SD card prepared by the wizard is still inserted during the flashing stage and that your PC and camera are on the same LAN/VLAN.

### Flashing reports an error

**Do not disconnect power.** Read the error shown by the wizard. The camera-side script attempts a stock APP restore if the custom write fails, but power should remain connected until the result is known.

---

## 🧑‍💻 Manual install / development

Instead of the one-line installer:

```bash
git clone https://github.com/4ddict/LSC-3215672-Decloud-Wizard.git
cd LSC-3215672-Decloud-Wizard
chmod +x install.sh
./install.sh
```

Useful commands:

```bash
./install.sh --version
./install.sh --help
```

Generated firmware, camera dumps, extracted files and Wi-Fi configs are ignored by `.gitignore` and should never be committed.

---

## ❤️ Credits

This wizard is an orchestration/user-experience layer built on the reverse-engineering work of other projects:

- **tasarren / lsc-tuya-toolkit** — SD boot hook, camera access, Wi-Fi and maintenance services  
  <https://github.com/tasarren/lsc-tuya-toolkit>
- **FluxAlchemist / LSC_AK3918AV130_cam_custom_firmware** — AK3918AV130 reverse engineering, `ak_rtsp`, firmware build and verified flash tooling  
  <https://github.com/FluxAlchemist/LSC_AK3918AV130_cam_custom_firmware>
- **OpenIPC / SmolRTSP** — RTSP library used by `ak_rtsp`  
  <https://github.com/OpenIPC/smolrtsp>

No stock LSC/Tuya firmware is distributed by this repository. The custom APP image is built locally from firmware dumped from the user's own camera.

---

## ⚖️ Disclaimer

Flashing embedded devices always carries risk. This project comes with no warranty. Unexpected hardware revisions, power loss, broken SD cards or software changes can potentially brick a camera.

The installer includes model/layout checks, a full stock backup and read-back verification to reduce that risk, but you use it at your own responsibility.

---

## 📄 License

The wizard/orchestration code is released under the **MIT License**. Downloaded upstream projects remain subject to their own licenses.
