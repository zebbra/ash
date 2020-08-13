defmodule Ash.Resource.Attribute do
  @moduledoc "Represents an attribute on a resource"

  defstruct [
    :name,
    :type,
    :allow_nil?,
    :generated?,
    :primary_key?,
    :writable?,
    :default,
    :update_default,
    :description,
    constraints: []
  ]

  @type t :: %__MODULE__{
          name: atom(),
          constraints: Keyword.t(),
          type: Ash.Type.t(),
          primary_key?: boolean(),
          default: (() -> term),
          update_default: (() -> term) | (Ash.record() -> term),
          writable?: boolean
        }

  alias Ash.OptionsHelpers

  @schema [
    name: [
      type: :atom,
      doc: "The name of the attribute."
    ],
    type: [
      type: {:custom, OptionsHelpers, :ash_type, []},
      doc: "The type of the attribute."
    ],
    constraints: [
      type: :keyword_list,
      doc:
        "Constraints to provide to the type when casting the value. See the type's documentation for more information."
    ],
    primary_key?: [
      type: :boolean,
      default: false,
      doc:
        "Whether or not the attribute is part of the primary key (one or more fields that uniquely identify a resource)"
    ],
    allow_nil?: [
      type: :boolean,
      default: true,
      doc: "Whether or not the attribute can be set to nil"
    ],
    generated?: [
      type: :boolean,
      default: false,
      doc:
        "Whether or not the value may be generated by the data layer. If it is, the data layer will know to read the value back after writing."
    ],
    writable?: [
      type: :boolean,
      default: true,
      doc: "Whether or not the value can be written to"
    ],
    update_default: [
      type: {:custom, __MODULE__, :validate_default, [:update]},
      doc:
        "A zero argument function, an {mod, fun, args} triple or `{:constant, value}`. If no value is provided for the attribute on update, this value is used."
    ],
    default: [
      type: {:custom, __MODULE__, :validate_default, [:create]},
      doc:
        "A zero argument function, an {mod, fun, args} triple or `{:constant, value}`. If no value is provided for the attribute on create, this value is used."
    ],
    description: [
      type: :string,
      doc: "An optional description for the attribute"
    ]
  ]

  @create_timestamp_schema @schema
                           |> OptionsHelpers.set_default!(:writable?, false)
                           |> OptionsHelpers.set_default!(:default, &DateTime.utc_now/0)
                           |> OptionsHelpers.set_default!(:type, :utc_datetime)

  @update_timestamp_schema @schema
                           |> OptionsHelpers.set_default!(:writable?, false)
                           |> OptionsHelpers.set_default!(:default, &DateTime.utc_now/0)
                           |> OptionsHelpers.set_default!(:update_default, &DateTime.utc_now/0)
                           |> OptionsHelpers.set_default!(:type, :utc_datetime)

  def transform(%{constraints: []} = attribute), do: {:ok, attribute}

  def transform(%{constraints: constraints, type: type} = attribute) do
    case type do
      {:array, type} ->
        with {:ok, new_constraints} <-
               NimbleOptions.validate(
                 Keyword.delete(constraints, :items),
                 Ash.Type.list_constraints()
               ),
             {:ok, item_constraints} <- validate_item_constraints(type, constraints) do
          {:ok,
           %{attribute | constraints: Keyword.put(new_constraints, :items, item_constraints)}}
        end

      type ->
        schema = Ash.Type.constraints(type)

        case NimbleOptions.validate(constraints, schema) do
          {:ok, constraints} ->
            {:ok, %{attribute | constraints: constraints}}

          {:error, error} ->
            {:error, error}
        end
    end
  end

  defp validate_item_constraints(type, constraints) do
    if Keyword.has_key?(constraints, :items) do
      schema = Ash.Type.constraints(type)

      case NimbleOptions.validate(constraints[:items], schema) do
        {:ok, item_constraints} ->
          {:ok, item_constraints}

        {:error, error} ->
          {:error, error}
      end
    else
      {:ok, constraints}
    end
  end

  def validate_default(value, _) when is_function(value, 0), do: {:ok, value}
  def validate_default({:constant, value}, _), do: {:ok, {:constant, value}}

  def validate_default({module, function, args}, _)
      when is_atom(module) and is_atom(function) and is_list(args),
      do: {:ok, {module, function, args}}

  def validate_default(nil, _), do: {:ok, nil}

  def validate_default(other, _) do
    {:error,
     "#{inspect(other)} is not a valid default. To provide a constant value, use `{:constant, #{
       inspect(other)
     }}`"}
  end

  @doc false
  def attribute_schema, do: @schema
  def create_timestamp_schema, do: @create_timestamp_schema
  def update_timestamp_schema, do: @update_timestamp_schema
end
