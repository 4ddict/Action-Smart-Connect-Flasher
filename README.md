# 📷 LSC Smart Connect Decloud Wizard

**Turn the €9.95 Action LSC Smart Connect indoor camera into a local RTSP camera — without needing to know Telnet, MTD flash layouts, cross-compilers, or Linux device names.**

> ✅ Originally tested on **3215672.2 / SI B26101**; additional community reports listed below\
> 📡 Local 1080p RTSP via `ak_rtsp`  
> ☁️ Removes the Tuya `anyka_ipc` cloud application from the APP partition  
> 💾 Creates a full stock firmware backup before flashing  
> 🐧 Interactive installer for Linux

---

## 🚀 Quick Install

Run this on your Linux computer:

```bash
curl -fsSL https://raw.githubusercontent.com/4ddict/Action-Smart-Connect-Flasher/main/install.sh -o /tmp/action-smart-connect-flasher.sh && bash /tmp/action-smart-connect-flasher.sh
```

That is all you need to download manually. The wizard downloads its helper files and the required upstream projects automatically.

**Do not run the complete wizard with `sudo`.** It will ask for your sudo password only when it needs to format/mount the SD card or install packages.

### Version 0.3.2

- Recognises the two additional camera labels reported in [issue #2](https://github.com/4ddict/Action-Smart-Connect-Flasher/issues/2), while retaining the exact MTD layout and backup checks.
- Downloads an official, SHA-256-verified Zig compiler when Zig is missing, including on Debian/Q4OS ;).
- Temporarily suppresses desktop automount for the selected SD card when udev/UDisks is available, and checks that it is unmounted before formatting.
- Documents the firmware's existing local camera controls below.

Version 0.3.1 already fixed detection of tools in `/sbin` and the separate Debian `fdisk` package. The complete wizard now refuses to run as root; start it as your regular user.

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


---

## 📦 What you need

| Item | Requirement |
| --- | --- |
| Camera | One of the exact labels in the compatibility table below |
| Computer | Linux PC/laptop |
| microSD | Any small card is sufficient; its contents will be erased |
| Wi-Fi | 2.4 GHz network |
| Network | Computer and camera must be able to reach each other locally |

The wizard currently supports dependency installation on **Arch/CachyOS**, **Debian/Ubuntu** and **Fedora-family** systems where the required packages are available.

The wizard checks the available tools before choosing `pacman`, APT or `dnf`. If everything is installed, it skips package installation. An existing Zig installation is used when it can run on the computer. Arch/CachyOS and Fedora first try their native Zig package when it is missing.

If Zig remains unavailable, the wizard can download **Zig 0.14.1 directly from ziglang.org** into its own cache after you approve dependency installation. It verifies the published SHA-256 checksum before extracting or running it. No additional APT repository is needed.

Automatic Zig downloads are configured for Linux x86 (32-bit), x86_64, AArch64, ARMv7 and RISC-V 64-bit hosts.

---

## ⚠️ Check the model before you start

Choose the exact article number and SI code printed on your camera or box:

| Article number | SI code | Evidence |
| --- | --- | --- |
| **3215672.2** | **B26101** | Original hardware-tested camera, Anyka AK3918AV130 |
| **3215672.2** | **C26101** | A successful installation with wizard 0.3.0 was reported in [issue #2](https://github.com/4ddict/Action-Smart-Connect-Flasher/issues/2) |
| **3215672.3** | **D26228** | A successful installation with wizard 0.3.0 was reported in [issue #2](https://github.com/4ddict/Action-Smart-Connect-Flasher/issues/2) |

The additional variants have not been independently hardware-tested by this project. Their inclusion is based on that user's successful installations. A matching label alone does not bypass the camera-side checks.

It is **not** for:

```text
3215672
3215672.1
```

Do not assume other SI codes or revisions are compatible. The wizard asks for the exact label and verifies the same MTD partition map on the camera before allowing a flash. A different layout is rejected.

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

## 🎛️ Live camera settings

The pinned upstream `ak_rtsp` firmware already includes a local, text-based control service on **TCP port 8091**. You can change settings after installation without rebuilding or reflashing firmware. This is not an HTTP API.

For example, connect from a computer on the same local network using netcat:

```bash
nc <camera-ip> 8091
```

If `nc` is missing on Debian/Q4OS/Ubuntu, install it with `sudo apt-get install netcat-openbsd`. On Arch/CachyOS the package is `openbsd-netcat`; on Fedora, `nmap-ncat` supplies the `ncat` command, which can be used in place of `nc`.

Type a command and press Enter. Start by reading the available settings:

```text
LIST
GET night.mode
GET night.state
```

| Command | Effect |
| --- | --- |
| `SET night.mode day` | Force day mode: IR illumination off and the IR-cut filter in its daytime position |
| `SET night.mode night` | Force night mode: IR illumination on and the IR-cut filter in its night position |
| `SET night.mode auto` | Return to automatic day/night switching |
| `GET night.state` | Read the current day/night state; this value is read-only |
| `SET isp.brightness 10` | Adjust brightness; accepted range is -50 to 50, with 0 as the neutral setting |

`isp.contrast`, `isp.saturation` and `isp.sharpness` also accept values from -50 to 50. `LIST` shows the exposure and automatic day/night tuning parameters as well. Change one setting at a time and record its previous value.

Day/night mode coordinates the IR LEDs, IR-cut filter and sensor settings; it is not an independent IR-LED switch. A mode change is applied by the monitor thread, so allow a moment before reading `night.state` again.

Replies beginning with `OK` acknowledge a change; `ERR` indicates a rejected command. Lines beginning with `LOG` are live camera logs. Press Ctrl+C to disconnect.

These are **runtime settings**: they reset when `ak_rtsp` restarts or the camera reboots. The service has no authentication or encryption. Keep port 8091 on a trusted local network and do not expose it to the Internet.

The protocol is implemented by upstream [control.c](https://github.com/FluxAlchemist/LSC_AK3918AV130_cam_custom_firmware/blob/3250e0f/src/ak_rtsp/control.c).

---

## 🔐 Wi-Fi handling

The installer:

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

### Zig is not available in Debian/Q4OS repositories

Version 0.3.2 can install the checksum-verified official compiler automatically after you accept dependency installation. You do not need to add a third-party repository. The first compiler run can take a long time on an older computer, especially while Zig prepares its ARM target libraries. Later runs can benefit from Zig's compiler cache; the wizard still rebuilds the executables.

### The SD card remounts while being prepared

The wizard uses a temporary udev rule to tell UDisks to ignore only the selected card while the wizard works on it. It removes the rule before card removal or when the wizard exits. It checks for remaining mounts before wiping or formatting.

Close file-manager windows using the card. If your desktop uses another automounter, or `udevadm` is unavailable, disable that desktop's automount option temporarily and rerun the wizard. Do not force formatting of a mounted card.

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
git clone https://github.com/4ddict/Action-Smart-Connect-Flasher.git
cd Action-Smart-Connect-Flasher
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
