defmodule DoubleEntryLedger.EventStore do
  @moduledoc """
  This module defines the EventStore behaviour.
  """
  alias Ecto.Changeset
  alias DoubleEntryLedger.{Repo, Event}

  @spec insert_event(map()) :: {:ok, Event.t()} | {:error, Ecto.Changeset.t()}
  def insert_event(attrs) do
    build_insert_event(attrs)
    |> Repo.insert()
  end

  @spec build_insert_event(Event.event_map()) :: Ecto.Changeset.t()
  def build_insert_event(attrs) do
    %Event{}
    |> Event.changeset(attrs)
  end

  def get_event(id) do
    case Repo.get(Event, id) do
      nil -> {:error, "Event not found"}
      event -> {:ok, event}
    end
  end

  @spec get_create_event_by_source(String.t(), String.t(), Ecto.UUID.t()) :: Event.t() | nil
  def get_create_event_by_source(source, source_idempk, instance_id) do
    Event
    |> Repo.get_by(action: :create, source: source, source_idempk: source_idempk, instance_id: instance_id)
    |> Repo.preload(processed_transaction: [entries: :account])
  end

  @spec mark_as_processed(Event.t(), Ecto.UUID.t()) :: {:ok, Event.t()} | {:error, Changeset.t()}
  def mark_as_processed(event, transaction_id) do
    event
    |> build_mark_as_processed(transaction_id)
    |> Repo.update()
  end

  @spec build_mark_as_processed(Event.t(), Ecto.UUID.t()) :: Changeset.t()
  def build_mark_as_processed(event, transaction_id) do
    event
    |> Changeset.change(status: :processed, processed_at: DateTime.utc_now(), processed_transaction_id: transaction_id)
    |> increment_tries()
  end

  @spec mark_as_occ_timeout(Event.t(), String.t()) :: {:ok, Event.t()} | {:error, Changeset.t()}
  def mark_as_occ_timeout(event, reason) do
    event
    |> build_add_error(reason)
    |> Changeset.change(status: :occ_timeout)
    |> Repo.update()
  end

  @spec mark_as_failed(Event.t(), String.t()) :: {:ok, Event.t()} | {:error, Changeset.t()}
  def mark_as_failed(event, reason) do
    event
    |> build_add_error(reason)
    |> Changeset.change(status: :failed)
    |> Repo.update()
  end

  @spec build_add_error(Event.t(), any()) :: Changeset.t()
  def build_add_error(event, error) do
    event
    |> Changeset.change(errors: [build_error(error) | event.errors])
    |> increment_tries()
  end

  @spec add_error(Event.t(), any()) :: {:ok, Event.t()} | {:error, Changeset.t()}
  def add_error(event, error) do
    event
    |> build_add_error(error)
    |> Repo.update()
  end

  defp build_error(error) do
    %{
      message: error,
      inserted_at: DateTime.utc_now(:microsecond),
    }
  end

  @spec increment_tries(Changeset.t()) :: Changeset.t()
  defp increment_tries(changeset) do
    current_tries = Changeset.get_field(changeset, :tries) || 0
    Changeset.put_change(changeset, :tries, current_tries + 1)
  end
end
