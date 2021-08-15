#!/bin/bash
rm .deploy_git/ -rf
hexo clean
hexo g 
hexo d
