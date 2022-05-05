dart test --coverage="tmp_coverage"

# requires enabling coverage via:
# > dart pub global activate coverage
format_coverage --lcov --in=tmp_coverage --out=tmp_coverage/coverage.lcov --packages=.packages --report-on=lib

# requires installing lcov
# > sudo apt install lcov
genhtml tmp_coverage/coverage.lcov -o tmp_coverage

echo "Open tmp_coverage/index.html to review code coverage results"