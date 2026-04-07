module example;
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

struct Person {
  int age;
  String name;
  Animal[] pets;
  Maybe{Person*} friend @Dessert({ .rename = "my_friend" });
  bool is_cool @Dessert({ .skip = true });
}

fn void? Person.serialize(&self, Serializer serializer) => 
  ser::impl_serialize(self, serializer);

fn void? Person.deserialize(&self, Deserializer deserializer) =>
  des::impl_deserialize(self, deserializer);

fn int main(String[] args) {
  Animal sharpie = { .name = "Sharpie", .specie = "Cat" };
  Person connor = { .age = 20, .name = "Connor", .is_cool = true };
  connor.pets = { sharpie };

  JsonSerializer s = json::serializer();
  JsonValue? json = ser::serialize(&s, connor);
  if (catch json) {
    io::printn("Error serializing");
    return -1;
  }
  
  json.print()!!;
  io::printn();
  
  Person? p = des::deserialize{Person}(&&json::deserializer(json.to_string()));
  if (catch p) {
    io::printn("Error deserializing");
    return -1;
  }

  io::printfn("Person named %s with a %s named %s", p.name, p.pets[0].specie, p.pets[0].name);
  
  return 0;
}
