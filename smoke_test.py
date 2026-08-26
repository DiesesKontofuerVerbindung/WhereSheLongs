from pathlib import Path
import tempfile


def main() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        probe = Path(tmp) / "probe.txt"
        probe.write_text("peking-smoke-test", encoding="utf-8")
        assert probe.read_text(encoding="utf-8") == "peking-smoke-test"

    print("SMOKE TEST PASSED")


if __name__ == "__main__":
    main()
