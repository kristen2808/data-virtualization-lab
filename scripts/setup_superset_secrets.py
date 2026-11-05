"""Create local Superset secrets without printing or replacing existing values."""

import os
from pathlib import Path
import secrets


def main():
    root = Path(__file__).resolve().parents[1] / "secrets" / "superset"
    if not (root / "metadata.env").is_file():
        raise SystemExit("Initialize the metadata database and metadata.env first; see README.md")
    root.parent.chmod(0o700)
    root.chmod(0o700)
    values = {
        "application.env": "SUPERSET_SECRET_KEY=" + secrets.token_urlsafe(64) + "\n",
        "admin.env": (
            "SUPERSET_ADMIN_USERNAME=admin\n"
            "SUPERSET_ADMIN_FIRST_NAME=Superset\n"
            "SUPERSET_ADMIN_LAST_NAME=Administrator\n"
            "SUPERSET_ADMIN_EMAIL=admin@localhost.invalid\n"
            "SUPERSET_ADMIN_PASSWORD=" + secrets.token_urlsafe(36) + "\n"
        ),
    }
    for name, content in values.items():
        try:
            fd = os.open(root / name, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        except FileExistsError:
            print("Preserved existing " + name)
        else:
            with os.fdopen(fd, "w") as output:
                output.write(content)
            print("Created " + name + " (mode 600); values not displayed")


if __name__ == "__main__":
    main()
