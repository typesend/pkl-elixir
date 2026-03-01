defmodule PklElixir.SchemaTest do
  use ExUnit.Case

  @schema_dir Path.expand("../fixtures/schema", __DIR__)

  # ── Single-class module: User.pkl ───────────────────────────────────

  defmodule TestUser do
    use PklElixir.Schema, source: "../../test/fixtures/schema/User.pkl"
  end

  describe "User (single class)" do
    @tag :integration
    test "generates struct with correct keys" do
      user = struct(TestUser)
      assert Map.has_key?(user, :name)
      assert Map.has_key?(user, :email)
      assert Map.has_key?(user, :age)
      assert Map.has_key?(user, :active)
    end

    @tag :integration
    test "enforce_keys for non-nullable properties" do
      # name, email, active are required; age is nullable
      assert_raise ArgumentError, ~r/missing required keys/, fn ->
        TestUser.from_map(%{"name" => "Alice"})
      end
    end

    @tag :integration
    test "from_map converts string-keyed map to struct" do
      user =
        TestUser.from_map(%{
          "name" => "Alice",
          "email" => "alice@example.com",
          "age" => 30,
          "active" => true
        })

      assert %TestUser{} = user
      assert user.name == "Alice"
      assert user.email == "alice@example.com"
      assert user.age == 30
      assert user.active == true
    end

    @tag :integration
    test "from_map accepts nullable fields as nil" do
      user =
        TestUser.from_map(%{
          "name" => "Bob",
          "email" => "bob@example.com",
          "age" => nil,
          "active" => false
        })

      assert user.age == nil
    end
  end

  # ── Multi-class module: Shape.pkl ───────────────────────────────────

  defmodule TestShape do
    use PklElixir.Schema, source: "../../test/fixtures/schema/Shape.pkl"
  end

  describe "Shape (multi-class module)" do
    @tag :integration
    test "skips abstract class, generates concrete submodules" do
      refute function_exported?(TestShape, :__struct__, 0)
      assert Code.ensure_loaded?(TestShape.Circle)
      assert Code.ensure_loaded?(TestShape.Rectangle)
      assert Code.ensure_loaded?(TestShape.Point)
    end

    @tag :integration
    test "Circle struct" do
      circle = TestShape.Circle.from_map(%{"radius" => 5.0})

      assert %TestShape.Circle{} = circle
      assert circle.radius == 5.0
    end

    @tag :integration
    test "Rectangle struct" do
      rect = TestShape.Rectangle.from_map(%{"width" => 10.0, "height" => 20.0})

      assert %TestShape.Rectangle{} = rect
      assert rect.width == 10.0
      assert rect.height == 20.0
    end

    @tag :integration
    test "Point struct with nullable label" do
      point = TestShape.Point.from_map(%{"x" => 1.0, "y" => 2.0, "label" => nil})

      assert %TestShape.Point{} = point
      assert point.x == 1.0
      assert point.y == 2.0
      assert point.label == nil
    end

    @tag :integration
    test "Point struct with label set" do
      point = TestShape.Point.from_map(%{"x" => 0.0, "y" => 0.0, "label" => "origin"})

      assert point.label == "origin"
    end

    @tag :integration
    test "enforce_keys on Rectangle rejects missing width" do
      assert_raise ArgumentError, ~r/missing required keys.*"width"/, fn ->
        TestShape.Rectangle.from_map(%{"height" => 10.0})
      end
    end
  end

  # ── Listing type and nested structs: Order.pkl ──────────────────────

  defmodule TestOrder do
    use PklElixir.Schema, source: "../../test/fixtures/schema/Order.pkl"
  end

  describe "Order (Listing type, nested structs)" do
    @tag :integration
    test "generates Order and LineItem submodules" do
      assert Code.ensure_loaded?(TestOrder.Order)
      assert Code.ensure_loaded?(TestOrder.LineItem)
    end

    @tag :integration
    test "Order.from_map converts Listing<LineItem> to structs" do
      order =
        TestOrder.Order.from_map(%{
          "id" => "order-1",
          "customer" => "Alice",
          "items" => [
            %{"product" => "Widget", "quantity" => 2, "price" => 9.99},
            %{"product" => "Gadget", "quantity" => 1, "price" => 24.99}
          ],
          "discount_code" => nil
        })

      assert %TestOrder.Order{} = order
      assert order.id == "order-1"
      assert order.customer == "Alice"
      assert order.discount_code == nil
      assert length(order.items) == 2

      [item1, item2] = order.items
      assert %TestOrder.LineItem{} = item1
      assert item1.product == "Widget"
      assert item1.quantity == 2
      assert item1.price == 9.99
      assert %TestOrder.LineItem{} = item2
    end

    @tag :integration
    test "Order.from_map with empty items list" do
      order =
        TestOrder.Order.from_map(%{
          "id" => "order-2",
          "customer" => "Bob",
          "items" => [],
          "discount_code" => "SAVE10"
        })

      assert order.items == []
      assert order.discount_code == "SAVE10"
    end
  end

  # ── :class option ────────────────────────────────────────────────────

  defmodule TestOrderOnly do
    use PklElixir.Schema,
      source: "../../test/fixtures/schema/Order.pkl",
      class: "Order"
  end

  describe ":class option" do
    @tag :integration
    test "generates struct directly on calling module" do
      assert function_exported?(TestOrderOnly, :__struct__, 0)
      order = struct(TestOrderOnly)
      assert Map.has_key?(order, :id)
      assert Map.has_key?(order, :customer)
      assert Map.has_key?(order, :items)
    end

    @tag :integration
    test "from_map works on the calling module" do
      order =
        TestOrderOnly.from_map(%{
          "id" => "x",
          "customer" => "y",
          "items" => [],
          "discount_code" => nil
        })

      assert %TestOrderOnly{id: "x", customer: "y", items: []} = order
    end
  end

  # ── Reflector ────────────────────────────────────────────────────────

  describe "Reflector" do
    @tag :integration
    test "reflect returns class metadata" do
      {:ok, classes} =
        PklElixir.Reflector.reflect(Path.join(@schema_dir, "User.pkl"))

      assert Map.has_key?(classes, "User")
      user = classes["User"]
      assert user["name"] == "User"
      assert user["isAbstract"] == false
      assert is_map(user["properties"])
      assert Map.has_key?(user["properties"], "name")
    end

    @tag :integration
    test "reflect with :class option filters classes" do
      {:ok, classes} =
        PklElixir.Reflector.reflect(
          Path.join(@schema_dir, "Shape.pkl"),
          class: "Circle"
        )

      assert Map.keys(classes) == ["Circle"]
    end

    @tag :integration
    test "reflect captures abstract modifier" do
      {:ok, classes} =
        PklElixir.Reflector.reflect(Path.join(@schema_dir, "Shape.pkl"))

      assert classes["Shape"]["isAbstract"] == true
      assert classes["Circle"]["isAbstract"] == false
    end

    @tag :integration
    test "reflect captures doc comments" do
      {:ok, classes} =
        PklElixir.Reflector.reflect(Path.join(@schema_dir, "User.pkl"))

      assert classes["User"]["docComment"] == "A registered user."
    end

    @tag :integration
    test "reflect captures type info for nullable properties" do
      {:ok, classes} =
        PklElixir.Reflector.reflect(Path.join(@schema_dir, "User.pkl"))

      age_type = classes["User"]["properties"]["age"]["type"]
      assert age_type["kind"] == "nullable"
      assert age_type["member"]["kind"] == "declared"
      assert age_type["member"]["name"] == "Int"
    end

    @tag :integration
    test "reflect captures type arguments for Listing" do
      {:ok, classes} =
        PklElixir.Reflector.reflect(Path.join(@schema_dir, "Order.pkl"))

      items_type = classes["Order"]["properties"]["items"]["type"]
      assert items_type["kind"] == "declared"
      assert items_type["name"] == "Listing"
      assert [%{"kind" => "declared", "name" => "LineItem"}] = items_type["typeArguments"]
    end
  end
end
