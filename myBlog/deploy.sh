#!/bin/bash
rm .deploy_git/ -rf
rm public -rf
echo "rm ./deploy_git"
hexo clean
hexo g 
hexo d
