"""Play the tunes in gfx/music.txt (melody pulse + bass saw). macOS: afplay. Usage: play_music.py [name ...]"""
import array, os, re, subprocess, sys, tempfile, wave

SR = 22050
STEP = {"theme": 7, "intro": 12, "dance": 8, "boss": 5}  # frames/step, from mtab in midnight.asm
FPS = 50
NOTES = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def parse(path):
    tunes = {}
    for line in open(path):
        line = line.split(";")[0].split()
        if line:
            tunes[line[0]] = line[1:]
    return tunes


def freq(tok):
    m = re.fullmatch(r"([A-G])(#?)(\d)", tok)
    midi = 12 * (int(m[3]) + 1) + NOTES[m[1]] + (m[2] == "#")
    return 440 * 2 ** ((midi - 69) / 12)


def voice(toks, n, wave_fn, gain):
    out = array.array("h")
    i = 0
    while i < len(toks):
        t = toks[i]
        j = i + 1
        if t != ".":  # '-' holds the previous note
            while j < len(toks) and toks[j] == "-":
                j += 1
        cnt = (j - i) * n
        if t == ".":
            out.extend([0] * cnt)
        else:
            f = freq(t)
            on = int(cnt * 0.85)  # short release before the next step
            out.extend(int(gain * wave_fn((k * f / SR) % 1)) for k in range(on))
            out.extend([0] * (cnt - on))
        i = j
    return out


def render(tunes, name):
    n = int(STEP[name] / FPS * SR)
    mel = voice(tunes[name], n, lambda p: 1 if p < 0.5 else -1, 6000)
    bass = voice(tunes[name + "b"], n, lambda p: 2 * p - 1, 8000)
    return array.array("h", (a + b for a, b in zip(mel, bass)))


def play(tunes, name):
    with tempfile.NamedTemporaryFile(suffix=".wav") as f:
        with wave.open(f.name, "wb") as w:
            w.setnchannels(1), w.setsampwidth(2), w.setframerate(SR)
            w.writeframes(render(tunes, name).tobytes())
        subprocess.run(["afplay", f.name])


if __name__ == "__main__":
    tunes = parse(os.path.join(os.path.dirname(__file__), "gfx", "music.txt"))
    names = [k for k in tunes if k + "b" in tunes]
    if sys.argv[1:]:
        for a in sys.argv[1:]:
            play(tunes, a)
    else:
        while True:
            for i, k in enumerate(names, 1):
                print(f"{i}) {k}")
            c = input("number/name, q=quit> ").strip()
            if c == "q":
                break
            c = names[int(c) - 1] if c.isdigit() and 0 < int(c) <= len(names) else c
            if c in names:
                play(tunes, c)
