const FLT_MAX = 3.402823466e+38
const FLT_MIN = 1.175494e-38

const INT_MAX = 2147483647
const INT_MIN = -2147483648

function Min( a, b ) {
	return ( a < b ) ? a : b
}
function Max( a, b ) {
	return ( a > b ) ? a : b
}

function Clamp( val, a, b ) {
	return Min( Max( val, a ), b )
}