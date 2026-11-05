"""Upgrade metadata and create a missing admin without changing existing users."""

import os
import subprocess


def main():
    subprocess.run(["superset", "db", "upgrade"], check=True)
    subprocess.run(["superset", "init"], check=True)

    from superset.app import create_app
    from superset import security_manager

    app = create_app()
    with app.app_context():
        username = os.environ["SUPERSET_ADMIN_USERNAME"]
        admin_role = security_manager.find_role("Admin")
        if admin_role is None:
            raise RuntimeError("Superset Admin role was not initialized")
        existing = security_manager.find_user(username=username)
        if existing is not None:
            if not existing.is_active or admin_role not in existing.roles:
                raise RuntimeError("Existing account is inactive or not Admin; left unchanged")
            print("Existing Superset administrator preserved; password unchanged.")
            return
        password = os.environ["SUPERSET_ADMIN_PASSWORD"]
        if len(password) < 16:
            raise ValueError("Use an administrator password of at least 16 characters")
        user = security_manager.add_user(
            username=username,
            first_name=os.environ["SUPERSET_ADMIN_FIRST_NAME"],
            last_name=os.environ["SUPERSET_ADMIN_LAST_NAME"],
            email=os.environ["SUPERSET_ADMIN_EMAIL"],
            role=admin_role,
            password=password,
        )
        if user is None or user is False:
            raise RuntimeError("Could not create Superset administrator; inspect account conflicts")
        print("Created Superset administrator.")


if __name__ == "__main__":
    main()
