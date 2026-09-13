unit SanityTests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TSanityTests = class
  public
    [Test]
    procedure TestHarnessIsWorking;
  end;

implementation

procedure TSanityTests.TestHarnessIsWorking;
begin
  Assert.AreEqual(2, 1 + 1);
end;

end.
