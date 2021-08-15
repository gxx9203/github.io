#!/bin/bash

git add . 
git commit  -s $1

git push origin  HEAD:refs/heads/ref/head/hexo

echo "Notice: please merger request on github"
