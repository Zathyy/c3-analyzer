module hello;
fn void foo()
{
	$switch $x:
		$case 1:
			#y += $x * $x;
		$case 2:
			#y += $x;
		$case 3:
			#y *= $x;
		$default:
			#y -= $x;
	$endswitch
}
