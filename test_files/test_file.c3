module hello;

bitstruct Bar : short
{
	int a : 0..2; // Exact bit ranges, bits 0-2
	uint b : 3..6;
	MyEnum c : 7..13;
}
