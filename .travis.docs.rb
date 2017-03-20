#!/usr/bin/env ruby

def check_preconditions
  if ENV['CI'] != 'true'
    puts 'The script is not run on Travis'
    exit 1
  end
  if ENV['TRAVIS_PULL_REQUEST'] != 'false'
    puts 'This script can\'t run for pull requests'
    exit 1
  end
  if !ENV['TRAVIS_TAG'] || ENV['TRAVIS_TAG'] !~ /^v\d{1,2}\.\d{1,2}\.\d{1,2}$/
    puts 'Skipping the docs generation because it\'s not a release build.'
    exit 0
  end
  # JOB: Ruby: 2.3.0 RUN_ON_LIVE_SERVER=0
  if !ENV['TRAVIS_JOB_NUMBER'].end_with?('.4')
    puts 'The document generation can be run only on the leader node.'
    exit 1
  end
  if ENV['TRAVIS_SECURE_ENV_VARS'] != 'true'
    puts 'There are no encrypted variables, add the secret to the .travis.yml'
    exit 1
  end
  if !ENV['GH_TOKEN']
    puts 'The GH_TOKEN variable is not set'
    exit 1
  end
end
check_preconditions

def version
  ENV['TRAVIS_TAG'][1..-1]
end

VERSION=version
DOCS_DIR='~/doc'

def switch_branch
  `git fetch origin +refs/heads/gh-pages:refs/remotes/origin/gh-pages`
  `git remote set-branches --add origin gh-pages`
  `git checkout --track -b gh-pages origin/gh-pages`
end

def generate_docs
  `yardoc --output-dir #{DOCS_DIR}`
end

def copy_docs
  `cp -r #{DOCS_DIR} docs/#{VERSION}`
  `rm docs/latest`
  `ln -s #{VERSION} docs/latest`
  `echo "      <li><a href='/hawkular-client-ruby/docs/#{VERSION}'>#{VERSION}</a></li>" >> docs/index.html`
end

def add_to_scm
  `git add -A`
  `git commit -m "Docs for version #{VERSION}."`
  `git remote add ad-hoc-origin https://hawkular-website-bot:#{ENV['GH_TOKEN']}@github.com/hawkular/hawkular-client-ruby.git`
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
