#!/bin/bash

## You need a Drupal installation + git + drush + coder_review enabled.
## This script must be run from somewhere in your Drupal installation.

DRUPAL_ROOT=`drush status --pipe drupal_root`

if [ ! -d $DRUPAL_ROOT/sites/all/modules ]; then
  if [ ! -d $DRUPAL_ROOT/sites/all ]; then
    echo "Directory $DRUPAL_ROOT/sites/all not found, please make sure that you run this script in a Drupal installation. Aborting."
    exit
  else
    mkdir $DRUPAL_ROOT/sites/all/modules
  fi
fi

if [ -d $DRUPAL_ROOT/sites/all/modules/pareview_temp ]; then
  # clean up test dir
  rm -rf $DRUPAL_ROOT/sites/all/modules/pareview_temp/*
else
  mkdir $DRUPAL_ROOT/sites/all/modules/pareview_temp
fi

cd $DRUPAL_ROOT/sites/all/modules/pareview_temp
# clone project quietly
git clone -q $1 test_candidate &> /dev/null
if [ $? -ne 0 ]; then
  echo "Git clone failed. Aborting."
  exit
fi
cd test_candidate

# checkout branch
# check if a branch name was passed on the command line
if [ $2 ]; then
  BRANCH_NAME=$2
  git checkout -q $BRANCH_NAME &> /dev/null
  if [ $? = 1 ]; then
    echo "Git checkout of branch $BRANCH_NAME failed. Aborting."
    exit
  fi
else
  # first try 7.x-?.x
  BRANCH_NAME=`git branch -a | grep -o -E "7\.x-[0-9]\.x$" | tail -n1`
  if [ -n "$BRANCH_NAME" ]; then
    git checkout -q $BRANCH_NAME &> /dev/null
  else
    # try 6.x-?.x
    BRANCH_NAME=`git branch -a | grep -o -E "6\.x-[0-9]\.x$" | tail -n1`
    if [ -n "$BRANCH_NAME" ]; then
      git checkout -q $BRANCH_NAME &> /dev/null
    else
      BRANCH_NAME=`git rev-parse --abbrev-ref HEAD`
      echo "It appears you are working in the \"$BRANCH_NAME\" branch in git. You should really be working in a version specific branch. The most direct documentation on this is <a href=\"http://drupal.org/node/1127732\">Moving from a master branch to a version branch.</a> For additional resources please see the documentation about <a href=\"http://drupal.org/node/1015226\">release naming conventions</a> and <a href=\"http://drupal.org/node/1066342\">creating a branch in git</a>."
    fi
  fi
fi
echo "Review of the $BRANCH_NAME branch:"

# get module/theme name
# if there is more than one info file we take the one with the shortest file name 
INFO_FILE=`ls *.info | awk '{ print length($0),$0 | "sort -n"}' | head -n1 | grep -o -E "[^[:space:]]*$"`
NAME=${INFO_FILE%.*}
PHP_FILES=`find . -not \( -name \*.tpl.php \) -and \( -name \*.module -or -name \*.php -or -name \*.inc -or -name \*.install -or -name \*.test \)`
CODE_FILES=`find . -name \*.module -or -name \*.php -or -name \*.inc -or -name \*.install -or -name \*.js -or -name \*.test`
# ensure $PHP_FILES is not empty
if [ -z "$PHP_FILES" ]; then
  # just set it to the current directory.
  PHP_FILES="."
  CODE_FILES="."
fi

# coder is not very good at detecting files in directories.
if [ -e $NAME.module ]; then
  CODER_PATH=sites/all/modules/pareview_temp/test_candidate/$NAME.module
else
  CODER_PATH=sites/all/modules/pareview_temp/test_candidate
fi
echo "<ul>"
# run coder
CODER=`drush coder-review no-empty minor comment i18n security sql style $CODER_PATH`
echo $CODER | grep -q "+"
if [ $? = 0 ]; then
  echo "<li>Run <a href=\"/project/coder\">coder</a> to check your style, some issues were found (please check the <a href=\"http://drupal.org/node/318\">Drupal coding standards</a>):"
  echo "<code>"
  echo "$CODER"
  echo "</code></li>"
fi

# README.txt present?
if [ ! -e README.txt ]; then
  echo "<li>README.txt is missing, see the <a href=\"http://drupal.org/node/447604\">guidelines for in-project documentation</a>.</li>"
else
# line length in README.txt
  LONG=`grep -c '.\{81\}' README.txt`
  if [ $LONG -gt "0" ]; then
    echo "<li>Lines in README.txt should not exceed 80 characters, see the <a href=\"http://drupal.org/node/447604\">guidelines for in-project documentation</a>.</li>"
  fi
fi
# LICENSE.txt present?
if [ -e LICENSE.txt ]; then
  echo "<li>Remove LICENSE.txt, it will be added by drupal.org packaging automatically.</li>"
fi
# translations folder present?
if [ -d translations ]; then
  echo "<li>Remove the translations folder, translations are done on http://localize.drupal.org</li>"
fi
# .DS_Store present?
if [ -e .DS_Store ]; then
  echo "<li>Remove .DS_Store from your repository.</li>"
fi
# "version" in info file?
grep -q -e "version[[:space:]]*=[[:space:]]*" $NAME.info
if [ $? = 0 ]; then
  echo "<li>Remove \"version\" from the info file, it will be added by drupal.org packaging automatically.</li>"
fi
# "project" in info file?
grep -q -e "project[[:space:]]*=[[:space:]]*" $NAME.info
if [ $? = 0 ]; then
  echo "<li>Remove \"project\" from the info file, it will be added by drupal.org packaging automatically.</li>"
fi
# "datestamp" in info file?
grep -q -e "datestamp[[:space:]]*=[[:space:]]*" $NAME.info
if [ $? = 0 ]; then
  echo "<li>Remove \"datestamp\" from the info file, it will be added by drupal.org packaging automatically.</li>"
fi
# @file in module file?
if [ -e $NAME.module ]; then
  grep -q " \* @file" $NAME.module
  if [ $? = 1 ]; then
    echo "<li>@file doc block is missing in the module file, see http://drupal.org/node/1354#files .</li>"
  fi  
fi
# @file in install file?
if [ -e $NAME.install ]; then
  grep -q " \* @file" $NAME.install
  if [ $? = 1 ]; then
    echo "<li>@file doc block is missing in the install file, see http://drupal.org/node/1354#files .</li>"
  fi  
fi
# ?> PHP delimiter at the end of any file?
FILES=`grep -l "^\?>" $PHP_FILES`
if [ $? = 0 ]; then
  echo "<li>The \"?>\" PHP delimiter at the end of files is discouraged, see http://drupal.org/node/318#phptags"
  echo "<code>"
  echo "$FILES"
  echo "</code></li>"
fi
# // Comments should start capitalized
# comments can take more than one line, so we cannot use this rules like this.
#COMMENTS=`grep -rn -E "^[[:space:]]*//[[:space:]]?[[:lower:]]" *`
#if [ $? = 0 ]; then
#  echo "<li>All comments should start capitalized."
#  echo "<code>"
#  echo "$COMMENTS"
#  echo "</code></li>"
#fi
# // Comments should end with a "."
#COMMENTS=`grep -rn -E "^[[:space:]]*//.*[[:alnum:]][[:space:]]*$" *`
#if [ $? = 0 ]; then
#  echo "<li>All comments should end with a \".\"."
#  echo "<code>"
#  echo "$COMMENTS"
#  echo "</code></li>"
#fi
# comments: space after //
COMMENTS=`grep -rn -E "^[[:space:]]*//[[:alnum:]].*" *`
if [ $? = 0 ]; then
  echo "<li>Comments: there should be a space after \"//\", see http://drupal.org/node/1354#inline"
  echo "<code>"
  echo "$COMMENTS"
  echo "</code></li>"
fi
# comment length > 80 chars
for FILE in $CODE_FILES; do
  COMMENTS=`grep -r -E "^[[:space:]]*//" $FILE | grep -E ".{81}"`
  if [ $? = 0 ]; then
    echo "<li>$FILE: comment lines should break at 80 characters, see http://drupal.org/node/1354#general"
    echo "<code>"
    echo "$COMMENTS"
    echo "</code></li>"
  fi
done
# comments not on a separate line
COMMENTS=`grep -n -E ".*[^[:space:]]+.*[^:]//[^\"']*$" $CODE_FILES`
if [ $? = 0 ]; then
  echo "<li>Comments should be on a separate line before the code line, see http://drupal.org/node/1354#inline"
  echo "<code>"
  echo "$COMMENTS"
  echo "</code></li>"
fi
# files[] not containing classes/interfaces
FILES=`grep -E "files\[\]" $NAME.info | grep -o -E "[^[:space:]=]+[[:space:]]*$"`
if [ $? = 0 ]; then
  for FILE in $FILES; do
    grep -q -E "^(abstract )?(class|interface) " $FILE &> /dev/null
    if [ $? -ne 0 ]; then
      echo "<li>$FILE in $NAME.info: It's only necessary to <a href=\"http://drupal.org/node/542202#files\">declare files[] if they declare a class or interface</a>.</li>"
    fi
  done
fi
# functions without doc blocks
for FILE in $PHP_FILES; do
  FUNCTIONS=`grep -E -B 1 "^function [[:alnum:]_]+.*\(.*\) ?\{" $FILE | grep -E -A 1 "^[[:space:]]*$"`
  if [ $? = 0 ]; then
    echo "<li>$FILE: all functions should have doxygen doc blocks, see http://drupal.org/node/1354#functions"
    echo "<code>"
    echo "$FUNCTIONS"
    echo "</code></li>"
  fi
done
# functions without module prefix
for FILE in $PHP_FILES; do
  FUNCTIONS=`grep -E "^function [[:alnum:]_]+.*\(.*\) \{" $FILE | grep -v -E "^function (_?$NAME|theme)"`
  if [ $? = 0 ]; then
    echo "<li>$FILE: all functions should be prefixed with your module/theme name to avoid name clashes. See http://drupal.org/node/318#naming"
    echo "<code>"
    echo "$FUNCTIONS"
    echo "</code></li>"
  fi
done
# indentation of @param/@return description
for FILE in $PHP_FILES; do
  COMMENTS=`grep -n -E -A 1 "(@return|@param)" $FILE | grep -v -E "(@return|@param|^--$)" | grep -v " \*   "`
  if [ $? = 0 ]; then
    echo "<li>$FILE: The description on the line after the @param/@return documentation is either missing or not formatted correctly. See http://drupal.org/node/1354#functions"
    echo "<code>"
    echo "$COMMENTS"
    echo "</code></li>"
  fi
done
# space before and after "==", "&&", "||" etc.
OPERATORS=`grep -rnI -E "([^[:space:]\!=]==|==[^[:space:]=]|[^[:space:]]&&|&&[^[:space:]]|[^[:space:]]\|\||\|\|[^[:space:]])" *`
if [ $? = 0 ]; then
  echo "<li>There should be a space before and after operators like ==, ===, && and ||. See http://drupal.org/node/318#controlstruct"
  echo "<code>"
  echo "$OPERATORS"
  echo "</code></li>"
fi
# bad line endings in files
FILES=`find . -type f`
BAD_LINES1=`file $FILES | grep "line terminators"`
# the "file" command does not detect bad line endings in HTML style files, so
# we run this grep command in addition.
BAD_LINES2=`grep -rlI $'\r' *`
if [ -n "$BAD_LINES1" ] || [ -n "$BAD_LINES2" ]; then
  echo "<li>Bad line endings were found, always use unix style terminators. See http://drupal.org/coding-standards#indenting"
  echo "<code>"
  echo "$BAD_LINES1"
  echo "$BAD_LINES2"
  echo "</code></li>"
fi
# space after "if ("
BAD_LINES=`grep -rnI -E "(if|elseif|foreach|for|switch) \( " *`
if [ $? = 0 ]; then
  echo "<li>There should be no space after the opening \"(\" of a control structure, see http://drupal.org/node/318#controlstruct"
  echo "<code>"
  echo "$BAD_LINES"
  echo "</code></li>"
fi
# space after "array("
BAD_LINES=`grep -rnI -E "array\( ." *`
if [ $? = 0 ]; then
  echo "<li>There should be no space after the opening \"(\" of an array, see http://drupal.org/node/318#array"
  echo "<code>"
  echo "$BAD_LINES"
  echo "</code></li>"
fi
# no space before assignment =
BAD_LINES=`grep -rn -E "^[^'\"><]*[^[:space:]\.=\!\"<>\+\-]=[^=][^'\"]*$" $CODE_FILES`
if [ $? = 0 ]; then
  echo "<li>Assignments should have a space before and after the operator, see http://drupal.org/node/318#operators"
  echo "<code>"
  echo "$BAD_LINES"
  echo "</code></li>"
fi
# old CVS $Id$ tags
FILES=`grep -n "\\$Id" *`
if [ $? = 0 ]; then
  echo "<li>Remove all old CVS \$Id tags, they are not needed anymore."
  echo "<code>"
  echo "$FILES"
  echo "</code></li>"
fi
# class names should use camelCase
BAD_LINES=`grep -rn -E "^(class|interface) [^[:space:]]*_" $PHP_FILES`
if [ $? = 0 ]; then
  echo "<li>Classes and Interfaces should use UpperCamel naming. See http://drupal.org/node/608152"
  echo "<code>"
  echo "$BAD_LINES"
  echo "</code></li>"
fi
# usage of t() in hook_schema()
if [ -e $NAME.install ]; then
  SCHEMA_LINE_NO=`grep -n -E "_schema\(\) ?\{" $NAME.install | cut -f1 -d:`
  if [ -n "$SCHEMA_LINE_NO" ]; then
    # @todo replace hard coded 1000 sed command with something that prints the
    # rest of a file
    SCHEMA_CONTENT=`sed -n $SCHEMA_LINE_NO,1000p $NAME.install`
    SCHEMA_END_NO=`echo "$SCHEMA_CONTENT" | grep -n -E "^\}" | cut -f1 -d: | head -n1`
    SCHEMA_CONTENT=`echo "$SCHEMA_CONTENT" | sed -n 1,"$SCHEMA_END_NO"p`
    BAD_LINES=`echo "$SCHEMA_CONTENT" | grep -E "[^[:alnum:]_]t\("`
    if [ $? = 0 ]; then
      echo "<li>Do not use t() in hook_schema(), this will only generate overhead for translators."
      echo "<code>"
      echo "$BAD_LINES"
      echo "</code></li>"
    fi
  fi
fi
echo "</ul>"

echo "<i>This automated report was generated with <a href=\"/sandbox/klausi/1320008\">PAReview.sh</a>, your friendly project application review script. Please report any bugs to klausi.</i>"

