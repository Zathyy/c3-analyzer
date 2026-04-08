module test;
import std;
import dessert;
import json;

struct Animal {
  String name;
  String specie;
}

fn void? Animal.serialize(&self, Serializer serializer) => 
  ser::impl_serialize(self, serializer);

fn void? Animal.deserialize(&self, Deserializer deserializer) => 
  des::impl_deserialize(self, deserializer);


enum State : (String name) {
  WAITING { "wait" },
  SLEEPING { "sleep" },
  RUNNING { "run" },
}

fn void? State.serialize(&self, Serializer serializer) => 
  ser::impl_serialize(self, serializer);

fn void? State.deserialize(&self, Deserializer deserializer) => 
  des::impl_deserialize(self, deserializer);

struct Person {
  int age;
  String name;
  Animal[] pets @Dessert({.skip_if_empty = true});
  Person* friend @Dessert({ .rename = "my_friend" });
  bool is_cool @Dessert({ .skip = true });
  long a;
  State state;
}

fn void? Person.serialize(&self, Serializer serializer) => 
  ser::impl_serialize(self, serializer);

fn void? Person.deserialize(&self, Deserializer deserializer) =>
  des::impl_deserialize(self, deserializer);


fn void t() @test {
  Animal sharpie = { .name = "Sharpie", .specie = "Cat" };
  Person connor = { .age = 20, .name = "Connor", .is_cool = true };
  Person amenda = { .age = 24, .name = "Amenda", .is_cool = false };
  connor.pets = { sharpie };
  connor.friend = &amenda;

  JsonSerializer s = json::serializer();
  JsonValue json = ser::serialize(&s, connor)!!;
  defer json.free();

  io::printn(json.to_pretty_string());

  Person p = des::deserialize{Person}(&&json::deserializer(json.to_string()))!!;

  io::printfn("%s\n%s", string::from_struct(mem, p), string::from_struct(mem, p.pets[0]));

  io::printfn("%s", string::from_struct(mem, *p.friend));

  assert(p.friend != null);
  assert(p.friend.name == "Amenda");

  // io::printfn("Person named %s with a %s named %s", p.name, p.pets[0].specie, p.pets[0].name);
}
