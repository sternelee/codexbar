import localUnitTest from './LocalUnit.test';
import logicUnitTest from './LogicUnit.test';

export default function testsuite() {
  localUnitTest();
  logicUnitTest();
}