# make sure to set MODE ("DEBUG", "PROFILE", or "RELEASE"), MAIN, and SRC before calling this
# you can add -Fu / -Fi lines to PATHS if you like
# you can add -dFOO to DEFINES if you like (for any value of FOO)
# you can set BIN if you want the binaries in a particular directory, it defaults to SRC + ../bin/
# you can set TESTCMD if you want to run a particular command instead of the obvious; it will be run relative to BIN
# you can set NORUN to skip running TESTCMD

# XXX -O4 should have LEVEL4 equivalent

if [ "${BIN}" = "" ]; then BIN="${SRC}../bin/"; fi

BINARY=`basename ${MAIN}`
if [ "${TESTCMD}" = "" ]; then TESTCMD="${BINARY}"; fi
if [ "${NORUN}" != "" ]; then TESTCMD="echo Compiled ${BINARY} successfully."; fi

PATHS="-FE${BIN} -FU${BIN}units -Fu${SRC}lib -Fi${SRC}lib ${PATHS}"

ulimit -v 800000

mkdir -vp "${BIN}"
mkdir -vp "${BIN}units"
SETTINGS="${MODE} ${DEFINES}"
touch ${BIN}SETTINGS
if [ "$(< ${BIN}SETTINGS)" != "${SETTINGS}" ]
then
  echo ""
  echo "compile: WARNING! CONFIGURATION CHANGED"
  echo "Old configuration: $(< ${BIN}SETTINGS)"
  echo "New configuration: ${SETTINGS}"
  echo "Consider using a different output directory!"
  echo ""
fi

echo -n "$SETTINGS" > ${BIN}SETTINGS

if [ "${MODE}" = "DEBUG" ]
then

  # DEBUG MODE:
  # echo compile: COMPILING - DEBUG MODE
  # add -vq to get warning numbers for {$WARN xxx OFF}
  fpc ${MAIN}.pas -l- -dDEBUG ${DEFINES} -Ci -Co -CO -Cr -CR -Ct -O- -gt -gl -gh -Sa -veiwnhb ${PATHS} 2>&1 | ${SRC}lib/filter.pl || exit 1
  cd $BIN &&
  ${TESTCMD} || exit 1

elif [ "${MODE}" = "FAST-DEBUG" ]
then

  # FASTER DEBUG MODE:
  # echo compile: COMPILING - DEBUG WITH OPTIMISATIONS
  fpc ${MAIN}.pas -l- -dDEBUG -dOPT ${DEFINES} -Ci -Co -CO -Cr -CR -Ct -O4 -gt -gl -Sa -veiwnhb ${PATHS} 2>&1 | ${SRC}lib/filter.pl || exit 1
  cd $BIN &&
  ${TESTCMD} || exit 1

elif [ "${MODE}" = "FAST" ]
then

  # FASTER MODE:
  # echo compile: COMPILING - SIMPLE OPTIMISATIONS ONLY, SYMBOL INFO INCLUDED
  fpc ${MAIN}.pas -l- -dOPT ${DEFINES} -O4 -Xs- -gl -veiwnhb ${PATHS} 2>&1 | ${SRC}lib/filter.pl || exit 1
  cd $BIN &&
  ${TESTCMD} || exit 1

elif [ "${MODE}" = "PROFILE-DEBUG" ]
then

  # DEBUG MODE WITH PROFILER:
  echo compile: COMPILING - DEBUG MODE WITH PROFILING ENABLED
  fpc ${MAIN}.pas -l- -gv -dDEBUG ${DEFINES} -Ci -Co -CO -Cr -CR -Ct -O- -gt -gl -gh -Sa -veiwnhb ${PATHS} 2>&1 | ${SRC}lib/filter.pl || exit 1
  cd $BIN &&
  echo compile: Running valgrind --tool=callgrind ${TESTCMD} &&
  valgrind --tool=callgrind --callgrind-out-file=callgrind.out ${TESTCMD};
  callgrind_annotate --auto=yes --inclusive=yes --tree=both callgrind.out > callgrind.inclusive.txt
  callgrind_annotate --auto=yes --inclusive=no --tree=none callgrind.out > callgrind.exclusive.txt


elif [ "${MODE}" = "FAST-PROFILE" ]
then

  # FASTER PROFILE MODE:
  echo compile: COMPILING - OPTIMISED BUILD WITH PROFILING ENABLED
  fpc ${MAIN}.pas -l- -gv -dOPT ${DEFINES} -Xs- -XX -B -v0einf -O4 ${PATHS} 2>&1 || exit 1
  cd $BIN &&
  echo compile: Running valgrind --tool=callgrind ${TESTCMD} &&
  valgrind --tool=callgrind --callgrind-out-file=callgrind.out ${TESTCMD};
  callgrind_annotate --auto=yes --inclusive=yes --tree=both callgrind.out > callgrind.inclusive.txt
  callgrind_annotate --auto=yes --inclusive=no --tree=none callgrind.out > callgrind.exclusive.txt

elif [ "${MODE}" = "PROFILE" ]
then

  # PROFILE MODE:
  echo compile: COMPILING - OPTIMISED BUILD WITH PROFILING ENABLED
  fpc ${MAIN}.pas -l- -dOPT ${DEFINES} -Xs- -XX -B -v0einf -O4 -OWALL -FW${BIN}opt-feedback ${PATHS} 2>&1 || exit 1
  cmp -s ${BIN}${BINARY} ${BIN}${BINARY}.last
  until [ $? -eq 0 ]; do
    echo compile: Trying to find optimisation stable point...
    mv ${BIN}${BINARY} ${BIN}${BINARY}.last || exit
    mv ${BIN}opt-feedback ${BIN}opt-feedback.last || exit
    fpc ${MAIN}.pas -l- -dOPT ${DEFINES} -Xs- -XX -B -O4 -OwALL -Fw${BIN}opt-feedback.last -OWALL -FW${BIN}opt-feedback ${PATHS} || exit 1
    cmp -s ${BIN}${BINARY} ${BIN}${BINARY}.last
  done
  echo compile: Final build...
  fpc ${MAIN}.pas -gv -a -l- -dOPT ${DEFINES} -Xs -XX -B -O4 -v0einf -OwALL -Fw${BIN}opt-feedback ${PATHS} 2>&1 || exit 1
  rm -f ${BIN}units/*.o ${BIN}units/*.ppu ${BIN}*.last ${BIN}callgrind.out &&
  cd $BIN &&
  echo compile: Running valgrind --tool=callgrind ${TESTCMD} &&
  valgrind --tool=callgrind --callgrind-out-file=callgrind.out ${TESTCMD};
  callgrind_annotate --auto=yes --inclusive=yes --tree=both callgrind.out > callgrind.inclusive.txt
  callgrind_annotate --auto=yes --inclusive=no --tree=none callgrind.out > callgrind.exclusive.txt

elif [ "${MODE}" = "MEMCHECK" ]
then

  # MEMCHECK MODE:
  echo compile: COMPILING - OPTIMISED BUILD WITH PROFILING ENABLED
  fpc ${MAIN}.pas -l- -dOPT ${DEFINES} -Xs- -XX -B -v0einf -O4 -OWALL -FW${BIN}opt-feedback ${PATHS} 2>&1 || exit 1
  cmp -s ${BIN}${BINARY} ${BIN}${BINARY}.last
  until [ $? -eq 0 ]; do
    echo compile: Trying to find optimisation stable point...
    mv ${BIN}${BINARY} ${BIN}${BINARY}.last || exit
    mv ${BIN}opt-feedback ${BIN}opt-feedback.last || exit
    fpc ${MAIN}.pas -l- -dOPT ${DEFINES} -Xs- -XX -B -O4 -OwALL -Fw${BIN}opt-feedback.last -OWALL -FW${BIN}opt-feedback ${PATHS} || exit 1
    cmp -s ${BIN}${BINARY} ${BIN}${BINARY}.last
  done
  echo compile: Final build...
  fpc ${MAIN}.pas -gv -a -l- -dOPT ${DEFINES} -Xs -XX -B -O4 -v0einf -OwALL -Fw${BIN}opt-feedback ${PATHS} 2>&1 || exit 1
  rm -f ${BIN}units/*.o ${BIN}units/*.ppu ${BIN}*.last ${BIN}callgrind.out &&
  echo compile: Running valgrind --tool=memcheck ${TESTCMD} &&
  cd $BIN &&
  valgrind --tool=memcheck --leak-check=full --show-leak-kinds=all --track-origins=yes --log-file=memcheck.txt ${TESTCMD};

else

  # RELEASE MODE:
  echo compile: COMPILING - RELEASE MODE
  fpc ${MAIN}.pas -l- -dRELEASE -dOPT ${DEFINES} -Xs- -XX -B -v0einf -O4 -OWALL -FW${BIN}opt-feedback ${PATHS} 2>&1 || exit 1
  cmp -s ${BIN}${BINARY} ${BIN}${BINARY}.last
  until [ $? -eq 0 ]; do
    echo compile: Trying to find optimisation stable point...
    mv ${BIN}${BINARY} ${BIN}${BINARY}.last || exit
    mv ${BIN}opt-feedback ${BIN}opt-feedback.last || exit
    fpc ${MAIN}.pas -l- -dRELEASE -dOPT ${DEFINES} -Xs- -XX -B -O4 -OwALL -Fw${BIN}opt-feedback.last -OWALL -FW${BIN}opt-feedback ${PATHS} || exit 1
    cmp -s ${BIN}${BINARY} ${BIN}${BINARY}.last
  done
  echo compile: Final build...
  fpc ${MAIN}.pas -a -l- -dRELEASE -dOPT ${DEFINES} -Xs -XX -B -O4 -v0einf -OwALL -Fw${BIN}opt-feedback ${PATHS} 2>&1 || exit 1
  cd $BIN &&
  rm -f ${BIN}/units/*.o ${BIN}units/*.ppu ${BIN}*.last &&
  ls -al ${BIN}${BINARY} &&
  perl -E 'say ("executable size: " . (-s $ARGV[0]) . " bytes")' ${BIN}${BINARY} &&
  cd $BIN &&
  time ${TESTCMD} || exit 1

fi
