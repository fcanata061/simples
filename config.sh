#!/bin/bash

WORK="${WORK:-$PWD/work}"
LOGS="${LOGS:-$PWD/logs}"
REPO="${REPO:-$PWD/repo}"
INSTALL="${INSTALL:-$PWD/install}"
DB="${DB:-$PWD/packages.db}"
PARALLEL=${PARALLEL:-$(nproc)}
