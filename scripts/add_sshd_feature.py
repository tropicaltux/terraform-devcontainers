import argparse
import commentjson
from pathlib import Path


def load_spec(path: Path) -> dict:
    """Load the devcontainer.json file."""
    try:
        return commentjson.loads(path.read_text(encoding="utf-8"))
    except commentjson.JSONLibraryException as err:
        raise Exception(f"{path} is not valid JSON: {err}")


def ensure_ssh_feature(spec: dict) -> bool:
    """Return True if spec modified; False if feature already present."""

    SSH_FEATURE_ID = "ghcr.io/devcontainers/features/sshd:1"

    features = spec.setdefault("features", {})
    if SSH_FEATURE_ID in features:
        return False
    features[SSH_FEATURE_ID] = {}
    return True


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Add SSH server feature to .devcontainer/devcontainer.json")
    parser.add_argument("--workspace", required=True, type=Path,
                        help="Path to the project root containing .devcontainer")

    workspace_path = parser.parse_args().workspace.expanduser().resolve()
    devcontainer_path = workspace_path / ".devcontainer" / "devcontainer.json"

    if not devcontainer_path.exists():
        raise Exception(f"'{devcontainer_path}' not found")

    spec = load_spec(devcontainer_path)

    if ensure_ssh_feature(spec):
        devcontainer_path.write_text(commentjson.dumps(spec, indent=2, ensure_ascii=False) + "\n",
                           encoding="utf-8")
        print(f"SSH feature added to {devcontainer_path}")
    else:
        print(f"SSH feature already present in {devcontainer_path}")


if __name__ == "__main__":
    main()
