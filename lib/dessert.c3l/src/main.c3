module example @if($feature(DESSERT_EXAMPLE));
import std;
import dessert;
import json;
import derive;

struct Animal {
  String name;
  String specie;
}

fn void? Animal.serialize(&self, Serializer serializer) => 
  ser::impl_serialize(self, serializer);

fn void? Animal.deserialize(&self, Deserializer deserializer) => 
  des::impl_deserialize(self, deserializer);

struct Person {
  int age;
  String name;
  Animal[] pets;
  int x;
  union @DField({ .tagged_by = "x" }) {
    int foo;
    double bar;
  }
  Maybe{Person*} friend @DField({ .rename = "my_friend" });
  bool is_cool @DField({ .skip = true });
}

// fn void? Person.serialize(&self, Serializer serializer) => 
//   ser::impl_serialize(self, serializer);

// fn void? Person.deserialize(&self, Deserializer deserializer) =>
//   des::impl_deserialize(self, deserializer);


// fn int main(String[] args) {
//   Animal sharpie = { .name = "Sharpie", .specie = "Cat" };
//   Person connor = { .age = 20, .name = "Connor", .is_cool = true, .x = 1, .bar = 0.2 };
//   connor.pets = { sharpie };
//
//   JsonSerializer s = json::serializer();
//   JsonValue? json = ser::serialize(&s, connor);
//   if (catch json) {
//     io::printn("Error serializing");
//     return -1;
//   }
//   
//   json.print()!!;
//   io::printn();
//   
//   // Person? p = des::deserialize{Person}(&&json::deserializer(json.to_string()));
//   // if (catch p) {
//   //   io::printn("Error deserializing");
//   //   return -1;
//   // }
//   //
//   // io::printfn("Person named %s with a %s named %s", p.name, p.pets[0].specie, p.pets[0].name);
//   
//   return 0;
// }

// $expand(derive(Response::name, dessert::serialize));
// struct Response {
//   int kind;
//   union params @DField({ .tagged_by = "kind" }) {
//     int first;
//     double second;
//     String third;
//   }
// }

union MyUnion @DUnion({ .inlined = true }) {
  int first;
  double second;
  String third;
}

$expand(derive(Request::name, dessert));
struct Request {
  int kind;
  MyUnion p @DField({ .tagged_by = "kind" });
}

fn void main() {
  Request req = { .kind = 1, .p = {.second = 2.2} };
  String s = ser::serialize(&&json::string_serializer(), req)!!;
  io::printn(s);

  Request p = des::deserialize{Request}(&&json::deserializer(s))!!;
  io::printn("DESERIALIZED:");
  io::printn(p.kind);
  io::printn(p.p.second);

  // Request req2 = { .kind = 2, .third = "Wow" };
  // s = ser::serialize(&&json::string_serializer(), req2)!!;
  // io::printn(s);
  //
  // Response res = { .kind = 2, .params = { .third = "Wow" }};
  // s = ser::serialize(&&json::string_serializer(), res)!!;
  // io::printn(s);
}
