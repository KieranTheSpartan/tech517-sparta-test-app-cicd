#!/bin/bash

git add .

echo "Enter commit message:"
read commitMessage

if [ -z "$commitMessage" ]; then
  echo "Commit message cannot be empty."
  exit 1
fi

git commit -m "$commitMessage"
git push

