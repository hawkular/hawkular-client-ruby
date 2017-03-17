#!/usr/bin/env ruby

def check_preconditions
  exit 1 if ENV['TRAVIS_SECURE_ENV_VARS'] != 'true'
  exit 1 if !ENV['GH_TOKEN']
  exit 1 if ENV['CI'] != 'true'
  exit 1 if ENV['TRAVIS_PULL_REQUEST'] != 'false'
  if !ENV['TRAVIS_TAG'] || ENV['TRAVIS_TAG'] !~ /^v\d{1,2}\.\d{1,2}\.\d{1,2}$/
    puts 'Skipping the docs generation because it\'s not a release build.'
    exit 0
  end
end
check_preconditions

def version
  ENV['TRAVIS_TAG'][1..-1]
end

VERSION=version
DOCS_DIR='~/doc'

def switch_branch
  `git checkout gh-pages`
end

def generate_docs
  `yardoc --output-dir #{DOCS_DIR}`
end

def copy_docs
  `cp -r #{DOCS_DIR} docs/#{VERSION}`
  `rm docs/latest`
  `ln -s #{VERSION} docs/latest`
  `echo "      <li><a href='/docs/#{VERSION}'>#{VERSION}</a></li>" >> docs/index.html`
end

def add_to_scm
  `git add -A`
  `git commit -m "Docs for version #{VERSION}."`
  `git remote add ad-hoc-origin https://hawkular-website-bot:#{GH_TOKEN}@github.com/hawkular/hawkular-client-ruby.git`
  `git push ad-hoc-origin gh-pages`
end

def main
  puts 'generating docs for version ' + VERSION
  generate_docs

  puts 'switching branch to gh-pages..'
  switch_branch

  puts 'copying docs..'
  copy_docs
  
  puts 'pushing back to gh-pages..'
  add_to_scm
end

main
