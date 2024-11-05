defmodule DoubleEntryLedger.UpdateEvent do
  @moduledoc """
  Helper functions for updating events.
  """
  alias Ecto.Multi
  alias DoubleEntryLedger.{
    Event, Transaction, EventStore, TransactionStore, Repo
  }

  import DoubleEntryLedger.OccRetry, only: [retry: 2]
  import DoubleEntryLedger.EventHelper, only: [transaction_data_to_transaction_map: 2]

  @spec process_update_event(Event.t()) :: {:ok, Transaction.t(), Event.t()} | {:error, String.t()}
  def process_update_event(event) do
    case fetch_create_event_transaction(event) do
      {:ok, transaction, _} ->
        update_transaction_and_event(event, transaction)
      {:pending_error, error, _} ->
        EventStore.add_error(event, error)
        {:error, error}
      {:error, error, _} ->
        {:error, error}
    end
  end

  @spec fetch_create_event_transaction(Event.t()) ::
    {:ok, Transaction.t(), Event.t()} | {(:error | :pending_error), String.t(), Event.t()}
  def fetch_create_event_transaction(%{source: source, source_id: source_id, instance_id: id}) do
    case EventStore.get_create_event_by_source(source, source_id, id) do
      %Event{processed_transaction: %{id: _} = transaction} = event ->
        {:ok, transaction, event}
      %Event{id: id, status: :pending} = event ->
        {:pending_error, "Create event has not yet been processed (event_id: #{id})", event}
      %Event{id: id, status: :failed} = event ->
        {:error, "Create event has failed (event_id: #{id})", event}
      nil ->
        {:error, "Event not found", nil}
    end
  end

  @spec update_transaction_and_event(Event.t(), Transaction.t()) ::
    {:ok, Transaction.t(), Event.t()} | {:error, String.t()}
  def update_transaction_and_event(%{instance_id: id, transaction_data: td} = event, transaction) do
    case transaction_data_to_transaction_map(td, id) do
      {:ok, transaction_map} ->
        retry(&update_transaction_and_event/3, [event, transaction, transaction_map])
      {:error, error} ->
        EventStore.mark_as_failed(event, error)
        {:error, error}
    end
  end

  @spec update_transaction_and_event(Event.t(), Transaction.t(), map()) ::
    {:ok, Transaction.t(), Event.t()} | {:error, String.t()}
  def update_transaction_and_event(event, transaction, attrs) do
    case build_update_transaction_and_event(transaction, event, attrs) |> Repo.transaction() do
      {:ok, %{
        update_transaction: %{transaction: transaction},
        update_event: update_event}} ->
        {:ok, transaction, update_event}
      {:error, error} ->
        EventStore.mark_as_failed(event, error)
        {:error, error}
    end
  end

  @spec build_update_transaction_and_event(Transaction.t(), Event.t(), map()) :: Ecto.Multi.t()
  def build_update_transaction_and_event(transaction, event, attr) do
    Multi.new()
    |> Multi.run(:update_transaction, fn repo, _ ->
        TransactionStore.build_update(transaction, attr)
        |> repo.transaction()
      end)
    |> Multi.run(:update_event, fn repo, %{update_transaction: %{transaction: td}} ->
        EventStore.build_mark_as_processed(event, td.id)
        |> repo.update()
      end)
  end
end
