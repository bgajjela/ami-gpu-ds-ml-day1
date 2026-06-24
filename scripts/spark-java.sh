# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Bharath Kumar Gajjela
# shellcheck shell=bash
# Spark/Java environment for interactive login shells (Java 21 LTS).
#
# JAVA_HOME, SPARK_HOME, SPARK_LOCAL_DIRS, and PYSPARK_PYTHON are also
# embedded directly in the /usr/local/bin/spark-submit, pyspark, pyspark311,
# pyspark312, pyspark313 wrapper scripts — so those commands work in ALL
# contexts (scripts, cron, ssh non-interactive, Jupyter kernels, systemd)
# without sourcing this file.
export JAVA_HOME=/opt/nix/langs/java
export SPARK_HOME=/opt/nix/langs/spark
export PATH="$SPARK_HOME/bin:$JAVA_HOME/bin:$PATH"

# Default PySpark interpreter — override with PYSPARK_PYTHON env var.
# Also set in /usr/local/bin/pyspark wrapper so it applies outside login shells.
export PYSPARK_PYTHON=${PYSPARK_PYTHON:-/opt/nix/envs/base/bin/python}

# Spark shuffle on EBS, not tmpfs (/tmp is noexec + size-capped).
# Also embedded in each wrapper script.
export SPARK_LOCAL_DIRS=/opt/spark-local
