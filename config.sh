#!/bin/bash

WORK="${WORK:-$PWD/work}"
LOGS="${LOGS:-$PWD/logs}"
REPO="${REPO:-$PWD/repo}"
INSTALL="${INSTALL:-$PWD/install}"
DB="${DB:-$PWD/packages.db}"
PARALLEL=${PARALLEL:-$(nproc)}
USE_FAKEROOT=${USE_FAKEROOT:-0}  # 0 = não, 1 = sim
