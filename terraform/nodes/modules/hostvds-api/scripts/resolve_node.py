#!/usr/bin/env python3
from pathlib import Path
import sys

REPO_ROOT = Path(__file__).resolve().parents[5]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from services.providers.resolvers.hostvds_openstack import main  # noqa: E402


if __name__ == "__main__":
    main()
