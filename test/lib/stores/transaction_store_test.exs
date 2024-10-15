defmodule DoubleEntryLedger.TransactionStoreTest do
  @moduledoc """
  This module tests the TransactionStore module.
  """
  use ExUnit.Case, async: true
  use DoubleEntryLedger.RepoCase
  import DoubleEntryLedger.{AccountFixtures, InstanceFixtures, TransactionFixtures}
  alias DoubleEntryLedger.{Account, TransactionStore, Transaction, Balance, Repo}

  describe "save successful transaction" do

    setup [:create_instance, :create_accounts]

    test "create transaction with 2 accounts", %{instance: inst, accounts: [a1, a2, _, _]} do
      attr = transaction_attr(instance_id: inst.id, entries: [
        %{type: :debit, amount: Money.new(100, :EUR), account_id: a1.id},
        %{type: :credit, amount: Money.new(100, :EUR), account_id: a2.id}
      ])
      TransactionStore.create(attr)

      assert %{
        pending: %Balance{amount: -100, credit: 0, debit: 100 },
        posted: %Balance{amount: 0, credit: 0, debit: 0 },
        available: 0,
        type: :debit,
      } = Repo.get!(Account, a1.id)
      assert %{
        pending: %Balance{amount: -100, credit: 100, debit: 0 },
        posted: %Balance{amount: 0, credit: 0, debit: 0 },
        available: 0,
        type: :credit,
      } = Repo.get!(Account, a2.id)
    end

    test "update transaction", %{instance: inst, accounts: [a1, a2, _, _]} do
      attr = transaction_attr(instance_id: inst.id, entries: [
        %{type: :debit, amount: Money.new(100, :EUR), account_id: a1.id},
        %{type: :credit, amount: Money.new(100, :EUR), account_id: a2.id}
      ])
      {:ok, %{id: id}} = TransactionStore.create(attr)
      trx = Repo.get!(Transaction, id)
      TransactionStore.update(trx, %{status: :posted})

      assert %{
        pending: %Balance{amount: 0, credit: 0, debit: 0 },
        posted: %Balance{amount: 100, credit: 0, debit: 100 },
        available: 100, type: :debit,
      } = Repo.get!(Account, a1.id)
      assert %{
        pending: %Balance{amount: 0, credit: 0, debit: 0 },
        posted: %Balance{amount: 100, credit: 100, debit: 0 },
        available: 100, type: :credit,
      } = Repo.get!(Account, a2.id)
    end

    test "create transaction with 3 accounts", %{instance: inst, accounts: [a1, a2, a3, _]} do
      attr = transaction_attr(status: :posted,
        instance_id: inst.id, entries: [
          %{type: :debit, amount: Money.new(50, :EUR), account_id: a1.id},
          %{type: :credit, amount: Money.new(100, :EUR), account_id: a2.id},
          %{type: :debit, amount: Money.new(50, :EUR), account_id: a3.id},
          ])
      TransactionStore.create(attr)

      assert %{
               posted: %Balance{amount: 50, credit: 0, debit: 50 },
               pending: %Balance{amount: 0, credit: 0, debit: 0 },
               available: 50,
               type: :debit,
             } = Repo.get!(Account, a1.id)
      assert %{
               posted: %Balance{amount: 50, credit: 0, debit: 50 },
               pending: %Balance{amount: 0, credit: 0, debit: 0 },
               available: 50,
               type: :debit,
             } = Repo.get!(Account, a3.id)
      assert %{
               posted: %Balance{amount: 100, credit: 100, debit: 0 },
               pending: %Balance{amount: 0, credit: 0, debit: 0 },
               available: 100,
               type: :credit,
             } = Repo.get!(Account, a2.id)
    end
  end

  defp create_instance(_ctx) do
    %{instance: instance_fixture()}
  end

  defp create_accounts(%{instance: instance}) do
    %{instance: instance, accounts: [
      account_fixture(instance_id: instance.id, type: :debit),
      account_fixture(instance_id: instance.id, type: :credit),
      account_fixture(instance_id: instance.id, type: :debit),
      account_fixture(instance_id: instance.id, type: :credit)
    ]}
  end
end
