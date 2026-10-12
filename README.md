# Mole Companion 0.3.0

**Keep an eye on your Moles from one place.** Mole Companion turns a CC:Tweaked computer and monitor into a station for watching multiple mining turtles. Choose a turtle to see its status, recent Mole output, and unfamiliar blocks it has mined, or ask it to return home.

Use **Mole 1.6.1 or newer** on your turtles. Wireless support stays optional; enable and pair it through `mole companion`.

## What you need

- A normal or advanced CC:Tweaked computer.
- A monitor connected to that computer. A normal monitor works; an advanced monitor also supports clicking buttons.
- A wireless modem or Ender modem connected to the computer.
- Each turtle needs its pickaxe, a wireless or Ender modem, and Mole 1.6.1 or newer.

Ordinary wireless modems have limited range. Deep mining may lose contact with a surface station. Ender modems remove that distance limit. The station and turtle still need their chunks loaded; this program does not load chunks.

## Download and start

Open the computer and type:

```text
wget https://raw.githubusercontent.com/Nom4d-temp/mole-companion/main/companion.lua companion
companion
```

This shows the command guide. Use `companion pair` to connect a turtle, or `companion start` to open the status display.

## Guided setup

1. **Connect a monitor.** Place it next to the computer. The companion checks for it and shows a test message. If several are connected, choose one from a numbered list.
2. **Connect a modem.** Place a wireless or Ender modem next to the computer. Wired modems are identified as unsuitable for contacting wireless turtles. If equipment is missing, attach it and press Enter to retry; `q` exits setup.
3. **Try the demo now:** run `companion demo`. It displays two fictional turtles and a sample unfamiliar block. Return commands are disabled and demo turtles are never saved.
4. **Pair a turtle:** run `companion pair` on the computer. This opens guided pairing immediately. Keep the turtle nearby with its modem equipped.
5. The station clearly shows **STATION COMPUTER ID** and **PAIRING CODE**, with a five-minute countdown. On the turtle, run `mole companion`, choose **1**, and follow its numbered steps. Enter the displayed ID and six-digit code. Invalid entries and missing modems can be retried.
6. When the turtle replies, the station shows its ID/name. Press **Y** if it is yours, or **N** to wait for the correct turtle. Choose a friendly name; Enter keeps the current name.
7. Both devices confirm the connection. Pairing closes back to the computer command prompt. Run `companion start` to open the display; it shows **Paired - waiting for Mole to run** until you use `mole new` or `mole resume` on the turtle.

Press Escape on the station to cancel pairing. If confirmation times out, keep the devices nearby, check chunks and modems, then run `companion pair` to retry. Existing pairings are retained until a new pairing is confirmed. On an already paired turtle, option **3** in `mole companion` checks the connection; option **1** re-pairs, and option **2** disables reporting.


The companion does not automatically replace the computer's startup file. If you want it to open on boot, add `shell.run("companion", "start")` to your own startup program.

## Everyday controls

| Key or command | Action |
| --- | --- |
| `companion` | Show the command overview |
| `companion start` | Open turtle status and activity display |
| `companion pair` | Open guided turtle pairing |
| `companion demo` | Preview with simulated data |
| `companion help` | Show the short control list |
| `companion update` | Install the latest program and clear all station settings |
| `companion remove` | Fully delete the program and station data after confirmation |
| Left / Right / Tab | Select a turtle |
| R, then Y | Ask the selected turtle to return home |
| D | Show unfamiliar block discoveries |
| L | Show recent Mole messages |
| Up / Down | Scroll the current list |
| P | Pair another turtle |
| Escape | Cancel pairing or a return confirmation |
| Q | Close the companion; turtles keep working |

Advanced monitors have **Prev**, **Next**, **Return**, and **Pair** buttons. Confirm returns with Y on the computer. A normal monitor uses the computer's keyboard controls.

The screen adapts to its size. If it is too small, add monitor blocks. Computer controls remain available if the monitor is detached. Reattach the same monitor/modem to reconnect; restart the companion to select equipment with a different peripheral name.

## What the station tells you

- Current job state, fuel, world Y, depth, and distance right/forward from the starting chest. This is Mole's tracked position, not GPS. During recovery it is labelled uncertain.
- Recent Mole messages, wrapped for your monitor. This is a Mole activity log, not a complete remote CraftOS terminal or keyboard.
- Each unfamiliar block's ID, optional readable name, and count reported by the turtle. Discoveries do not change mining decisions.
- Return request state: sent, accepted, completed, rejected, or unconfirmed. “Sent” alone does not mean the turtle received it. An unconfirmed request is not left queued indefinitely for a later reconnection.
- Time since the last message when contact is lost. Last-known data remains visible; it is not live position.

The companion retains 80 recent messages and up to 128 distinct discoveries per turtle/job in memory. It supports up to 32 paired turtles. Pairings and names persist; live status/logs/discoveries are refreshed by the turtle after station restart. When connected, a returning turtle will finish its current action safely before following Mole's usual return routine. Recovery and emergency escape remain in charge when a normal return cannot proceed.

## If something needs attention

| Problem | What to do |
| --- | --- |
| No monitor / modem | Attach the requested peripheral, then press Enter |
| Wired modem detected | Use a wireless or Ender modem instead |
| No turtle reply | Check Mole is 1.6.0 or newer, then check both chunks, modems, and range |
| No recent contact | Last-known data is displayed; check loading and range before sending a return |
| Return unconfirmed | Check connection and turtle status; do not assume it is returning |
| Pairing file damaged | Existing files are kept. Rename `mole-companion-data`, start again, and pair turtles again |

Pairing prevents accidental control of the wrong turtle, but Rednet is not encrypted or authenticated against other players. This first version is for trusted worlds/servers. Do not treat its pairing code/token as protection against a malicious player.

## Update or remove

Run `companion update` for a **clean install** of the latest GitHub program. Successful updates erase all pairings, names, and settings, even if the version is unchanged. No old program backup is kept. Run `companion pair` afterward to pair your turtles again, then `companion start` to open the display. Failed or invalid downloads leave the current installation intact.

Run `companion remove`, then type `yes`, to delete the program and all its saved data without a backup. Any other answer cancels. If your own startup program launches Companion, remove that launch line yourself; unrelated startup files are kept.

These commands work without a monitor or modem and do not change the turtles or their quarry jobs. After an update or removal, a turtle may still report to its former station; re-pair it or disable reporting with `mole companion`.

## AI disclosure

Mole Companion was generated with OpenAI's ChatGPT from human requirements and checked with simulated CC:Tweaked tests. Minecraft testing is still needed, especially for wireless range and real modem behavior.
