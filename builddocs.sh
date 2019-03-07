#!/bin/bash

find src/ -name '*.nim' -type f -exec nim doc {} \;