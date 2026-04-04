module example;

// import foo; // this should work too
import foo::bar;

fn int main()
{
    foo::bar::test(5, 5);
}