#!/bin/bash

## You need git + phpcs + coder 7.x-2.x.

if [[ $# -lt 1 || $1 == "--help" || $1 == "-h" ]]
then
  echo "Usage:    `basename $0` GIT-URL [BRANCH]"
  echo "          `basename $0` DIR-PATH"
  echo "Examples:"
  echo "  `basename $0` http://git.drupal.org/project/rules.git"
  echo "  `basename $0` http://git.drupal.org/project/rules.git 6.x-1.x"
  echo "  `basename $0` sites/all/modules/rules"
  exit
fi

# check if the first argument is valid directory.
if [ -d $1 ]; then
 cd $1
# otherwise treat the user input as git URL.
else
  if [ -d pareview_temp ]; then
    # clean up test dir
    rm -rf pareview_temp
  else
    mkdir pareview_temp
  fi

  # clone project quietly
  git clone -q $1 pareview_temp &> /dev/null
  if [ $? -ne 0 ]; then
    echo "Git clone failed. Aborting."
    exit 1
  fi
  cd pareview_temp

  # Check if a default branch is checked out.
  BRANCH_NAME=`git branch`
  if [ -z "$BRANCH_NAME" ]; then
    echo "Git default branch is not set, see <a href=\"https://www.drupal.org/node/1659588\">the documentation on setting a default branch</a>."
  fi

  # checkout branch
  # check if a branch name was passed on the command line
  if [ $2 ]; then
    BRANCH_NAME=$2
    git checkout -q $BRANCH_NAME &> /dev/null
    if [ $? = 1 ]; then
      echo "Git checkout of branch $BRANCH_NAME failed. Aborting."
      exit 1
    fi
  else
    # First try ?.x-?.x. We want to get the highest core compatibility number,
    # i.e. 8.x-1.x before 7.x-1.x. So we take the last match.
    BRANCH_NAME=`git branch -a | grep -o -E "[0-9]\.x-[0-9]\.x$" | tail -n1`
    if [ -n "$BRANCH_NAME" ]; then
      git checkout -q $BRANCH_NAME &> /dev/null
    else
      BRANCH_NAME=`git branch -a | sed -e 's/ *remotes\/origin\///p' | tail -n1`
      echo "It appears you are working in the \"$BRANCH_NAME\" branch in git. You should really be working in a version specific branch. The most direct documentation on this is <a href=\"https://www.drupal.org/node/1127732\">Moving from a master branch to a version branch.</a> For additional resources please see the documentation about <a href=\"https://www.drupal.org/node/1015226\">release naming conventions</a> and <a href=\"https://www.drupal.org/node/1066342\">creating a branch in git</a>."
    fi
  fi
  if [ $BRANCH_NAME != "master" ]; then
    # Check that there is no master branch.
    MASTER_BRANCH=`git branch -a | grep -E "^  remotes/origin/master$"`
    if [ $? = 0 ]; then
      echo "There is still a master branch, make sure to set the correct default branch: https://www.drupal.org/node/1659588 . Then remove the master branch, see also step 6 and 7 in https://www.drupal.org/node/1127732"
    fi
    git checkout -q $BRANCH_NAME &> /dev/null
  fi
  TAG_CLASH=`git tag -l | grep $BRANCH_NAME`
  if [ $? = 0 ]; then
    echo "There is a git tag that has the same name as the branch $BRANCH_NAME. Make sure to remove this tag to avoid confusion."
    exit 1
  fi
  # Check that no branch patterns with the suffix "dev" are used.
  # Check also that no tag name patterns are used as branches.
  BRANCH_ERRORS=`git branch -a | grep -E "([0-9]\.x-[0-9]\.x-dev$|[0-9]\.[0-9]-[0-9]\.x$|[0-9]\.x-[0-9]\.[0-9]$|[0-9]\.[0-9]-[0-9]\.[0-9]$)"`
  if [ $? = 0 ]; then
    echo "The following git branches do not match the release branch pattern, you should remove/rename them. See https://www.drupal.org/node/1015226"
    echo "<code>"
    echo "$BRANCH_ERRORS"
    echo "</code>"
  fi
  BRANCH_VERSION=`git rev-parse --short HEAD`
  echo "Review of the $BRANCH_NAME branch (commit $BRANCH_VERSION):"
fi

# Get module/theme name.
# If there is more than one info file we take the one with the shortest file
# name. We look for *.info (Drupal 7) and *.info.yml (Drupal 8) files.
INFO_FILE=`ls | grep '\.info\(\.yml\)\?$' | awk '{ print length($0),$0 | "sort -n"}' | head -n1 | grep -o -E "[^[:space:]]*$"`
NAME=${INFO_FILE%%.*}
PHP_FILES=`find . -name \*.module -or -name \*.php -or -name \*.inc -or -name \*.install -or -name \*.test -or -name \*.profile`
NON_TPL_FILES=`find . -not \( -name \*.tpl.php \) -and \( -name \*.module -or -name \*.php -or -name \*.inc -or -name \*.install -or -name \*.test -name \*.profile \)`
CODE_FILES=`find . -name \*.module -or -name \*.php -or -name \*.inc -or -name \*.install -or -name \*.js -or -name \*.test`
TEXT_FILES=`find . -name \*.module -or -name \*.php -or -name \*.inc -or -name \*.install -or -name \*.js -or -name \*.test -or -name \*.css -or -name \*.txt -or -name \*.info`
FILES=`find . -path ./.git -prune -o -type f -print`
INFO_FILES=`find . -name \*.info`
# ensure $PHP_FILES is not empty
if [ -z "$PHP_FILES" ]; then
  # just set it to the current directory.
  PHP_FILES="."
  CODE_FILES="."
  NON_TPL_FILES="."
fi
echo "<ul class='reports'>"

# README.txt present?
if [ ! -e README.txt ] && [ ! -e README.md ] ; then
  echo "<li><span>README.txt or README.md is missing, see the <a href=\"https://www.drupal.org/node/447604\">guidelines for in-project documentation</a>.</span></li>"
fi
# LICENSE.txt present?
if [ -e LICENSE.txt ]; then
  echo "<li><span>Remove LICENSE.txt, it will be added by drupal.org packaging automatically.</span></li>"
fi
if [ -e LICENSE ]; then
  echo "<li><span>Remove the LICENSE, drupal.org packaging will add a LICENSE.txt file automatically.</span></li>"
fi
# translations folder present?
if [ -d translations ]; then
  echo "<li><span>Remove the translations folder, translations are done on http://localize.drupal.org</span></li>"
fi
# .DS_Store present?
CHECK_FILES=".DS_Store .idea node_modules .project .sass-cache .settings vendor"
for FILE in $CHECK_FILES; do
  FOUND=`find . -name $FILE`
  if [ -n "$FOUND" ]; then
    echo "<li><span>Remove all $FILE files from your repository.</span></li>"
  fi
done
# Backup files present?
BACKUP=`find . -name "*~"`
if [ ! -z "$BACKUP" ]; then
  echo "<li><span>Remove all backup files from your repository:</span>"
  echo "<code>"
  echo "$BACKUP"
  echo "</code></li>"
fi

for FILE in $INFO_FILES; do
  # "version" in info file?
  grep -q -e "version[[:space:]]*=[[:space:]]*" $FILE
  if [ $? = 0 ]; then
    echo "<li><span>Remove \"version\" from the $FILE file, it will be added by drupal.org packaging automatically.</span></li>"
  fi
  # "project" in info file?
  grep -q -e "project[[:space:]]*=[[:space:]]*" $FILE
  if [ $? = 0 ]; then
    echo "<li><span>Remove \"project\" from the $FILE file, it will be added by drupal.org packaging automatically.</span></li>"
  fi
  # "datestamp" in info file?
  grep -q -e "datestamp[[:space:]]*=[[:space:]]*" $FILE
  if [ $? = 0 ]; then
    echo "<li><span>Remove \"datestamp\" from the $FILE file, it will be added by drupal.org packaging automatically.</span></li>"
  fi
done

# ?> PHP delimiter at the end of any file?
BAD_LINES=`grep -l "^\?>" $NON_TPL_FILES`
if [ $? = 0 ]; then
  echo "<li><span>The \"?>\" PHP delimiter at the end of files is discouraged, see https://www.drupal.org/node/318#phptags</span>"
  echo "<code>"
  echo "$BAD_LINES"
  echo "</code></li>"
fi
# Functions without module prefix.
# Exclude *.api.php and *.drush.inc files.
CHECK_FILES=`echo "$PHP_FILES" | grep -v -E "(api\.php|drush\.inc)$"`
for FILE in $CHECK_FILES; do
  FUNCTIONS=`grep -E "^function [[:alnum:]_]+.*\(.*\) \{" $FILE | grep -v -E "^function (_?$NAME|theme|template|phptemplate)"`
  if [ $? = 0 ]; then
    echo "<li><span>$FILE: all functions should be prefixed with your module/theme name to avoid name clashes. See https://www.drupal.org/node/318#naming</span>"
    echo "<code>"
    echo "$FUNCTIONS"
    echo "</code></li>"
  fi
done
# bad line endings in files
BAD_LINES1=`file $FILES | grep "line terminators"`
# the "file" command does not detect bad line endings in HTML style files, so
# we run this grep command in addition.
BAD_LINES2=`grep -rlI $'\r' *`
if [ -n "$BAD_LINES1" ] || [ -n "$BAD_LINES2" ]; then
  echo "<li><span>Bad line endings were found, always use unix style terminators. See https://www.drupal.org/coding-standards#indenting</span>"
  echo "<code>"
  echo "$BAD_LINES1"
  echo "$BAD_LINES2"
  echo "</code></li>"
fi
# old CVS $Id$ tags
BAD_LINES=`grep -rnI "\\$Id" *`
if [ $? = 0 ]; then
  echo "<li><span>Remove all old CVS \$Id tags, they are not needed anymore.</span>"
  echo "<code>"
  echo "$BAD_LINES"
  echo "</code></li>"
fi
# PHP parse error check
for FILE in $PHP_FILES; do
  ERRORS=`php -l $FILE 2>&1`
  if [ $? -ne 0 ]; then
    echo "<li>$ERRORS</li>"
  fi
done
# \feff character check at the beginning of files.
for FILE in $TEXT_FILES; do
  ERRORS=`grep ^$'\xEF\xBB\xBF' $FILE`
  if [ $? = 0 ]; then
    echo "<li><span>$FILE: the byte order mark at the beginning of UTF-8 files is discouraged, you should remove it.</span></li>"
  fi
done

# run drupalcs
DRUPALCS=`phpcs --standard=Drupal --extensions=php,module,inc,install,test,profile,theme,js,css,info,txt,md .`
DRUPALCS_ERRORS=$?
if [ $DRUPALCS_ERRORS = 1 ]; then
  LINES=`echo "$DRUPALCS" | wc -l`
  if [ $LINES -gt 20 ]; then
    echo "<li><span><a href=\"https://www.drupal.org/project/coder\">Coder Sniffer</a> has found some issues with your code (please check the <a href=\"https://www.drupal.org/node/318\">Drupal coding standards</a>). See attachment.</span></li>"
  else
    echo "<li><span><a href=\"https://www.drupal.org/project/coder\">Coder Sniffer</a> has found some issues with your code (please check the <a href=\"https://www.drupal.org/node/318\">Drupal coding standards</a>).</span>"
    echo "<code>"
    echo "$DRUPALCS"
    echo "</code></li>"
    DRUPALCS_ERRORS=0
  fi
fi

# Run DrupalPractice
DRUPALPRACTICE=`phpcs --standard=DrupalPractice --extensions=php,module,inc,install,test,profile,theme .`
if [ $? = 1 ]; then
  echo "<li class='drupalpractice'><span><a href=\"https://www.drupal.org/project/drupalpractice\">DrupalPractice</a> has found some issues with your code, but could be false positives.</span>"
  echo "<code>"
  echo "$DRUPALPRACTICE"
  echo "</code></li>"
fi

# Run DrupalSecure
DRUPALSECURE=`phpcs --standard=DrupalSecure --extensions=php,module,inc,install,test,profile,theme .`
if [ $? = 1 ]; then
  echo "<li class='drupalsecure'><span><a href=\"https://www.drupal.org/sandbox/coltrane/1921926\">DrupalSecure</a> has found some issues with your code (please check the <a href=\"https://www.drupal.org/writing-secure-code\">Writing secure core</a> handbook).</span>"
  echo "<code>"
  echo "$DRUPALSECURE"
  echo "</code></li>"
fi

# Check if codespell is installed.
hash codespell 2>/dev/null
if [ $? = 0 ]; then
  # Run codespell.
  SPELLING=`codespell -d . 2>/dev/null`
  if [ ! -z "$SPELLING" ]; then
    echo "<li class='codespell'><span><a href=\"https://github.com/lucasdemarchi/codespell\">Codespell</a> has found some spelling errors in your code.</span>"
    echo "<code>"
    echo "$SPELLING"
    echo "</code></li>"
  fi
fi

# Check if the project contains automated tests.
D7_TEST_FILES=`find . -name \*\.test`
D8_TEST_DIRS=`find . -type d \( -iname test -or -iname tests \)`
# Do not throw this error for themes, they usually don't have tests.
if [ -z "$D7_TEST_FILES" ] && [ -z "$D8_TEST_DIRS" ] && [ ! -e template.php ] && [ ! -e *.theme ] ; then
  echo "<li class='tests'><span>No automated test cases were found, did you consider writing <a href=\"https://www.drupal.org/simpletest\">Simpletests</a> or <a href=\"https://www.drupal.org/phpunit\">PHPUnit tests</a>? This is not a requirement but encouraged for professional software development.</span></li>"
fi

echo "</ul>"

#echo "<i>This automated report was generated with <a href=\"https://www.drupal.org/project/pareviewsh\">PAReview.sh</a>, your friendly project application review script. You can also use the <a href=\"http://pareview.sh\">online version</a> to check your project. You have to get a <a href=\"https://www.drupal.org/node/1975228\">review bonus</a> to get a review from me.</i>"

if [[ $DRUPALCS_ERRORS = 1 ]]; then
  #echo -e "\n\n\n"
  echo "<code id='report-full'>"
  if [ -n "$DRUPALCS" ]; then
    echo "$DRUPALCS"
  fi
  echo "</code>"
fi
