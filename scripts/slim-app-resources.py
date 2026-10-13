"""Prepare smaller generated Syllivra bundle resources; source files stay intact."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import tempfile
import wave


def compact_frequency(counts, limit):
    if not isinstance(counts, dict) or type(limit) is not int or limit <= 0:
        raise ValueError("Expected a frequency dictionary and positive word limit")
    if any(not isinstance(word, str) or not word or type(count) is not int or count < 0
           for word, count in counts.items()):
        raise ValueError("Frequency words need nonnegative integer counts")
    if len(counts) <= limit:
        return counts
    cutoff = sorted(counts.values(), reverse=True)[limit - 1]
    # Keep every boundary tie; the runtime remains responsible for its existing cap.
    return {word: count for word, count in counts.items() if count >= cutoff}


def checked_bundle(bundle, source):
    if bundle.is_symlink() or not bundle.is_dir() or bundle.suffix not in [".app", ".appex"]:
        raise ValueError("Destination must be a generated app or extension bundle")
    bundle, source = bundle.resolve(), source.resolve()
    if bundle == source or source in bundle.parents or bundle in source.parents:
        raise ValueError("Source resources and generated bundle must be separate")
    return bundle


def pcm(path):
    with wave.open(str(path), "rb") as audio:
        return (audio.getnchannels(), audio.getsampwidth(), audio.getframerate(),
                audio.getnframes(), audio.readframes(audio.getnframes()))


def prepare_frequency(source, bundle):
    bundle = checked_bundle(bundle, source)
    core = Path(__file__).resolve().parents[1] / "SyllivraKernel/Sources/SyllivraKernel/FrequencyDictionary.swift"
    match = re.search(r"static let maxWords = ([0-9_]+)", core.read_text())
    if match is None:
        raise ValueError("Could not read the runtime frequency-word limit")
    limit = int(match[1].replace("_", ""))
    for language in ["de", "en", "es", "fr"]:
        name = f"{language}_frequency.json"
        counts = json.loads((source / name).read_text())
        compact = compact_frequency(counts, limit)
        output = bundle / name
        if output.is_symlink():
            raise ValueError("Generated frequency file must not be a symlink")
        encoded = json.dumps(compact, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n"
        output.write_text(encoded, encoding="utf-8")
        print(f"Frequency {language}: {len(counts)} source words; {len(compact)} eligible words; {len(encoded.encode('utf-8'))} bytes")


def prepare_sounds(source, bundle):
    bundle = checked_bundle(bundle, source)
    sounds = bundle / "Sounds"
    if sounds.is_symlink():
        raise ValueError("Generated sound directory must not be a symlink")
    sounds.mkdir(exist_ok=True)
    inputs = sorted(source.glob("*.wav"))
    if not inputs:
        raise ValueError("No source feedback sounds found")
    before, after = 0, 0
    with tempfile.TemporaryDirectory(prefix=".lossless-", dir=sounds) as temporary:
        temporary = Path(temporary)
        for original in inputs:
            expected = pcm(original)
            if expected[:3] != (2, 2, 48000):
                raise ValueError("Feedback source must use the verified stereo 16-bit 48 kHz PCM format")
            encoded = temporary / (original.stem + ".caf")
            decoded = temporary / original.name
            reference = temporary / (original.stem + "-reference.wav")
            subprocess.run(["/usr/bin/afconvert", "-f", "caff", "-d", "alac", str(original), str(encoded)], check=True)
            # Normalize headers/channel layout with Apple's decoder; Python 3.9 cannot read extensible WAV.
            for input_file, output_file in [(original, reference), (encoded, decoded)]:
                subprocess.run(["/usr/bin/afconvert", "-f", "WAVE", "-d", "LEI16", "-l", "Stereo",
                                str(input_file), str(output_file)], check=True)
            if reference.read_bytes() != decoded.read_bytes():
                raise ValueError(f"Lossless sound verification failed: {original.name}")
            output = sounds / encoded.name
            copied_wav = sounds / original.name
            if output.is_symlink() or copied_wav.is_symlink():
                raise ValueError("Generated sound files must not be symlinks")
            # Only retire a copied build resource after exact PCM preservation is proven.
            if copied_wav.exists() and pcm(copied_wav) != expected:
                raise ValueError(f"Copied sound differs from source: {original.name}")
            before += original.stat().st_size
            after += encoded.stat().st_size
            encoded.replace(output)
            copied_wav.unlink(missing_ok=True)
    print(f"Sounds: {len(inputs)} lossless PCM matches; {before} source bytes; {after} encoded bytes")


def self_test():
    counts = {"alpha": 100, "beta": 80, "gamma": 50, "delta": 50, "epsilon": 1}
    assert compact_frequency(counts, 3) == {"alpha": 100, "beta": 80, "gamma": 50, "delta": 50}
    assert compact_frequency(counts, 20) == counts
    assert compact_frequency({}, 3) == {}
    for invalid in [{"word": True}, {"word": -1}, {"word": "1"}, {"": 1}]:
        try:
            compact_frequency(invalid, 3)
        except ValueError:
            pass
        else:
            raise AssertionError("Malformed frequency counts must fail")
    with tempfile.TemporaryDirectory(prefix="syllivra-resource-test-") as temporary:
        root = Path(temporary)
        source = root / "source"
        source.mkdir()
        try:
            checked_bundle(source, source)
        except ValueError:
            pass
        else:
            raise AssertionError("Source directory must never be a generated destination")
        bundle = root / "Probe.app"
        bundle.mkdir()
        assert checked_bundle(bundle, source) == bundle.resolve()
        linked = root / "Linked.app"
        linked.symlink_to(source, target_is_directory=True)
        try:
            checked_bundle(linked, source)
        except ValueError:
            pass
        else:
            raise AssertionError("Symlink destinations must fail")
        sound_source = source / "Sounds"
        sound_source.mkdir()
        original = sound_source / "probe.wav"
        with wave.open(str(original), "wb") as audio:
            audio.setparams((2, 2, 48000, 0, "NONE", "not compressed"))
            audio.writeframes(b"\x01\x00\xff\xff" * 32)
        original_bytes = original.read_bytes()
        copied = bundle / "Sounds"
        copied.mkdir()
        (copied / original.name).write_bytes(original_bytes)
        prepare_sounds(sound_source, bundle)
        assert (copied / "probe.caf").is_file()
        assert not (copied / "probe.wav").exists()
        assert original.read_bytes() == original_bytes
    print("Frequency cutoff, ties, malformed data and generated-destination checks passed")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--kind", choices=["app", "keyboard"])
    parser.add_argument("--source", type=Path)
    parser.add_argument("--bundle", type=Path)
    arguments = parser.parse_args()
    if arguments.self_test:
        self_test()
    elif arguments.kind and arguments.source is not None and arguments.bundle is not None:
        if arguments.kind == "app":
            prepare_sounds(arguments.source, arguments.bundle)
        else:
            prepare_frequency(arguments.source, arguments.bundle)
    else:
        parser.error("Provide --self-test, or --kind/--source/--bundle")
